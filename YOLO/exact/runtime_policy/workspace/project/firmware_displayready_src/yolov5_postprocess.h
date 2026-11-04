#ifndef SOC_YOLOV5_POSTPROCESS_H
#define SOC_YOLOV5_POSTPROCESS_H

#include <stdint.h>

/* A head is HWC with three anchors per cell. Each anchor has
 * tx, ty, tw, th, objectness, then class_count signed INT8 logits.
 * The 256-entry LUT maps signed logits [-128, 127] to sigmoid Q0.15.
 * Anchors are integer pixel widths/heights at the final image scale.
 */
typedef struct {
    const volatile int8_t *tensor;
    const volatile uint16_t *anchors_wh;
    const volatile uint16_t *sigmoid_q15;
    uint32_t grid_w, grid_h, stride;
} soc_yolov5_head;

/* Coordinates are clipped to the image in unsigned Q16.16 pixels.
 * Scores are Q0.15. The structure is exactly 24 bytes in DDR.
 */
typedef struct {
    uint32_t x1_q16, y1_q16, x2_q16, y2_q16;
    uint32_t score_q15, class_id;
} soc_detection;

typedef struct {
    uint32_t class_count, image_w, image_h;
    uint32_t score_threshold_q15, iou_threshold_q15;
    uint32_t max_candidates, max_results;
} soc_yolov5_options;

enum {
    SOC_DETECT_OK = 0,
    SOC_DETECT_BAD_PARAMS = 1,
    SOC_DETECT_CANDIDATE_OVERFLOW = 2
};

uint32_t soc_yolov5_decode_nms(const soc_yolov5_head *heads,
                                uint32_t head_count,
                                const soc_yolov5_options *options,
                                volatile soc_detection *scratch,
                                volatile soc_detection *results,
                                uint32_t *candidate_count,
                                uint32_t *result_count);

#endif
