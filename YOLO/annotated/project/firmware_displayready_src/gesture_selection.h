// 架构导读：gesture_selection。
// 从检测结果中选择要发布的手势类别、框与置信度。
#ifndef SOC_GESTURE_SELECTION_H
#define SOC_GESTURE_SELECTION_H

#include <stdint.h>
#include "yolov5_postprocess.h"
#include "display_cmos2.h"

#define SOC_GESTURE_CLASS_COUNT 6u
#define SOC_GESTURE_FILTER_ALL UINT32_MAX

// 数据布局定义：typedef struct {；字段顺序与本文件使用它的接口保持一致。
typedef struct {
    uint32_t xy[2], score, class_id, chosen;
} soc_gesture_selection;

// 服务函数 soc_gesture_filter_valid。
// 接口参数：uint32_t filter；返回值及副作用由下列函数体定义。
// 参数入口：filter；类型、指针限定及返回约定沿用下列声明。
static inline uint32_t soc_gesture_filter_valid(uint32_t filter) {
    return filter == SOC_GESTURE_FILTER_ALL || filter < SOC_GESTURE_CLASS_COUNT;
}

/* Called after class-aware NMS. A missing detection stays chosen=0; it must
 * never be reported as class 0 (fist). Existing single-class filters remain
 * valid. ALL chooses the highest-scoring valid display box across six classes.
 */
static inline soc_gesture_selection soc_select_cmos2_gesture(
        const volatile soc_detection *detections, uint32_t count,
        uint32_t filter) {
    soc_gesture_selection selected = {{0u, 0u}, 0u, 0u, 0u};
    // 控制边界：!soc_gesture_filter_valid(filter)；仅在该条件成立时进入本分支。
    if (!soc_gesture_filter_valid(filter)) return selected;
    // 迭代边界：uint32_t i = 0; i < count; ++i；地址和计数随循环体中的原始更新前进。
    for (uint32_t i = 0; i < count; ++i) {
        const volatile soc_detection *d = &detections[i];
        // 控制边界：d->class_id >= SOC_GESTURE_CLASS_COUNT ||；仅在该条件成立时进入本分支。
        if (d->class_id >= SOC_GESTURE_CLASS_COUNT ||
            (filter != SOC_GESTURE_FILTER_ALL && d->class_id != filter) ||
            (selected.chosen && d->score_q15 <= selected.score)) continue;
        uint32_t q[4] = {d->x1_q16, d->y1_q16, d->x2_q16, d->y2_q16};
        uint32_t xy[2];
        // 控制边界：q[0] >= q[2] || q[1] >= q[3]；仅在该条件成立时进入本分支。
        if (q[0] >= q[2] || q[1] >= q[3]) continue;
        soc_display_map_cmos2(q, xy);
        // 控制边界：(xy[0] & 65535u) >= (xy[1] & 65535u) ||；仅在该条件成立时进入本分支。
        if ((xy[0] & 65535u) >= (xy[1] & 65535u) ||
            (xy[0] >> 16) >= (xy[1] >> 16)) continue;
        selected.xy[0] = xy[0]; selected.xy[1] = xy[1];
        selected.score = d->score_q15; selected.class_id = d->class_id;
        selected.chosen = 1u;
    }
    return selected;
}
#endif
