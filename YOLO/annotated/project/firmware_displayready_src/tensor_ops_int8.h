// 架构导读：tensor_ops_int8。
// 共享张量算子的布局检查和软件参考操作。
#ifndef SOC_TENSOR_OPS_INT8_H
#define SOC_TENSOR_OPS_INT8_H

#include <stdint.h>

#define SOC_TENSOR_OPS_ID 0x31504f54u /* "TOP1" in little-endian bytes */
enum { SOC_TOP_POOL=1, SOC_TOP_UPSAMPLE=2, SOC_TOP_CONCAT=3,
       SOC_TOP_LUT=4, SOC_TOP_ADD=5 };

typedef struct {
    uint32_t kind,input_h,input_w,input_c,aux_c;
    uint32_t kernel_h,kernel_w,stride_h,stride_w;
    uint32_t pad_top,pad_left,pad_bottom,pad_right,param;
} soc_tensor_shape;

typedef struct {
    uint32_t output_h,output_w,output_c;
    uint32_t input_bytes,aux_bytes,output_bytes;
} soc_tensor_layout;

/* HWC signed INT8. All buffers are disjoint. LUT indexes the raw input byte.
 * ADD is saturating signed INT8 addition and requires a shared zero point 0.
 * Pool pads with -128; nearest upsample repeats pixels. The caller validates
 * address ranges and disjointness before calling the operation.
 */
int soc_tensor_layout_int8(const soc_tensor_shape *shape,
                            soc_tensor_layout *layout);
// 服务函数 soc_tensor_run_int8。
// 接口参数：const volatile int8_t *input,；返回值及副作用由下列函数体定义。
void soc_tensor_run_int8(const volatile int8_t *input,
                          const volatile int8_t *aux,
                          volatile int8_t *output,
                          const soc_tensor_shape *shape,
                          const soc_tensor_layout *layout);

#endif
