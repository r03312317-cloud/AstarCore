#include "yolov5_postprocess.h"

static uint32_t sigmoid_at(const volatile uint16_t *lut, int8_t value) {
    uint32_t q = lut[(uint32_t)((int32_t)value + 128)];
    return q > 32767u ? 32767u : q;
}

static uint32_t product_q15(uint32_t a, uint32_t b) {
    return (a * b + 16384u) >> 15;
}

static uint32_t clip_q16(int64_t value, uint32_t limit) {
    if (value <= 0) return 0;
    uint64_t end = (uint64_t)limit << 16;
    return (uint64_t)value > end ? (uint32_t)end : (uint32_t)value;
}

static uint64_t intersection_area_q16(const volatile soc_detection *a,
                                      const volatile soc_detection *b) {
    uint32_t x1 = a->x1_q16 > b->x1_q16 ? a->x1_q16 : b->x1_q16;
    uint32_t y1 = a->y1_q16 > b->y1_q16 ? a->y1_q16 : b->y1_q16;
    uint32_t x2 = a->x2_q16 < b->x2_q16 ? a->x2_q16 : b->x2_q16;
    uint32_t y2 = a->y2_q16 < b->y2_q16 ? a->y2_q16 : b->y2_q16;
    if (x2 <= x1 || y2 <= y1) return 0;
    return ((uint64_t)(x2 - x1) * (y2 - y1)) >> 16;
}

static uint64_t area_q16(const volatile soc_detection *a) {
    return ((uint64_t)(a->x2_q16 - a->x1_q16) *
            (a->y2_q16 - a->y1_q16)) >> 16;
}

static int should_suppress(const volatile soc_detection *a,
                           const volatile soc_detection *b,
                           uint32_t iou_threshold_q15) {
    if (a->class_id != b->class_id) return 0;
    uint64_t intersection = intersection_area_q16(a, b);
    if (!intersection) return 0;
    uint64_t union_area = area_q16(a) + area_q16(b) - intersection;
    return intersection * 32768u >= union_area * iou_threshold_q15;
}

uint32_t soc_yolov5_decode_nms(const soc_yolov5_head *heads,
                                uint32_t head_count,
                                const soc_yolov5_options *options,
                                volatile soc_detection *scratch,
                                volatile soc_detection *results,
                                uint32_t *candidate_count,
                                uint32_t *result_count) {
    if (!heads || !options || !scratch || !results || !candidate_count ||
        !result_count || !head_count || head_count > 3u ||
        !options->class_count || options->class_count > 80u ||
        !options->image_w || options->image_w > 2048u ||
        !options->image_h || options->image_h > 2048u ||
        !options->score_threshold_q15 || options->score_threshold_q15 > 32767u ||
        !options->iou_threshold_q15 || options->iou_threshold_q15 > 32767u ||
        !options->max_candidates || options->max_candidates > 1024u ||
        !options->max_results || options->max_results > 64u ||
        options->max_results > options->max_candidates)
        return SOC_DETECT_BAD_PARAMS;
    *candidate_count = 0;
    *result_count = 0;
    for (uint32_t h = 0; h < head_count; ++h) {
        const soc_yolov5_head *head = &heads[h];
        if (!head->tensor || !head->anchors_wh || !head->sigmoid_q15 ||
            !head->grid_w || !head->grid_h || !head->stride ||
            head->grid_w > 2048u || head->grid_h > 2048u ||
            head->stride > 128u ||
            head->grid_w * head->stride != options->image_w ||
            head->grid_h * head->stride != options->image_h)
            return SOC_DETECT_BAD_PARAMS;
        uint32_t step = options->class_count + 5u;
        uint32_t cell_stride = 3u * step;
        for (uint32_t gy = 0; gy < head->grid_h; ++gy) {
            for (uint32_t gx = 0; gx < head->grid_w; ++gx) {
                uint32_t cell = (gy * head->grid_w + gx) * cell_stride;
                for (uint32_t anchor = 0; anchor < 3u; ++anchor) {
                    const volatile int8_t *p = head->tensor + cell + anchor * step;
                    uint32_t objectness = sigmoid_at(head->sigmoid_q15, p[4]);
                    if (objectness < options->score_threshold_q15) continue;
                    uint32_t best_class = 0, best_class_score = 0;
                    for (uint32_t cls = 0; cls < options->class_count; ++cls) {
                        uint32_t q = sigmoid_at(head->sigmoid_q15, p[5u + cls]);
                        if (q > best_class_score) {
                            best_class_score = q;
                            best_class = cls;
                        }
                    }
                    uint32_t score = product_q15(objectness, best_class_score);
                    if (score < options->score_threshold_q15) continue;
                    if (*candidate_count >= options->max_candidates)
                        return SOC_DETECT_CANDIDATE_OVERFLOW;
                    uint32_t sx = sigmoid_at(head->sigmoid_q15, p[0]);
                    uint32_t sy = sigmoid_at(head->sigmoid_q15, p[1]);
                    uint32_t sw = sigmoid_at(head->sigmoid_q15, p[2]);
                    uint32_t sh = sigmoid_at(head->sigmoid_q15, p[3]);
                    uint32_t aw = head->anchors_wh[2u * anchor];
                    uint32_t ah = head->anchors_wh[2u * anchor + 1u];
                    if (!aw || !ah || aw > 2048u || ah > 2048u)
                        return SOC_DETECT_BAD_PARAMS;
                    int64_t xc = ((int64_t)gx * head->stride << 16) +
                                 ((int64_t)(2u * sx) - 16384) * head->stride * 2;
                    int64_t yc = ((int64_t)gy * head->stride << 16) +
                                 ((int64_t)(2u * sy) - 16384) * head->stride * 2;
                    uint64_t width = ((uint64_t)(2u * sw) * (2u * sw) * aw) >> 14;
                    uint64_t height = ((uint64_t)(2u * sh) * (2u * sh) * ah) >> 14;
                    volatile soc_detection *candidate = &scratch[*candidate_count];
                    candidate->x1_q16 = clip_q16(xc - (int64_t)(width / 2u), options->image_w);
                    candidate->y1_q16 = clip_q16(yc - (int64_t)(height / 2u), options->image_h);
                    candidate->x2_q16 = clip_q16(xc + (int64_t)(width / 2u), options->image_w);
                    candidate->y2_q16 = clip_q16(yc + (int64_t)(height / 2u), options->image_h);
                    if (candidate->x1_q16 < candidate->x2_q16 &&
                        candidate->y1_q16 < candidate->y2_q16) {
                        candidate->score_q15 = score;
                        candidate->class_id = best_class;
                        ++*candidate_count;
                    }
                }
            }
        }
    }
    while (*result_count < options->max_results) {
        uint32_t best = options->max_candidates;
        uint32_t best_score = 0;
        for (uint32_t i = 0; i < *candidate_count; ++i) {
            uint32_t q = scratch[i].score_q15;
            if (q > best_score) {
                best = i;
                best_score = q;
            }
        }
        if (best == options->max_candidates) break;
        results[*result_count] = scratch[best];
        ++*result_count;
        scratch[best].score_q15 = 0;
        for (uint32_t i = 0; i < *candidate_count; ++i)
            if (scratch[i].score_q15 &&
                should_suppress(&results[*result_count - 1u], &scratch[i],
                                options->iou_threshold_q15))
                scratch[i].score_q15 = 0;
    }
    return SOC_DETECT_OK;
}
