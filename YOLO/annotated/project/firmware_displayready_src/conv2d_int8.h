// 架构导读：conv2d_int8。
// 卷积参数与数据布局检查及保留的软件参考运算。
#ifndef SOC_CONV2D_INT8_H
#define SOC_CONV2D_INT8_H

#include <stdint.h>

/* A portable HWC, signed-INT8 standard-convolution frontend for the NPU's
 * A[M,K] x B[K,N] command. Padding contributes signed zero. The caller owns
 * B is packed in consecutive groups of at most eight output channels. Each
 * group's rows are K-major. The caller owns GEMM completion, bias,
 * requantization and activation.
 */
#define SOC_CONV2D_ID 0x32435631u /* "1VC2" in little-endian memory */

typedef struct {
    uint32_t input_h, input_w, input_c, output_c;
    uint32_t kernel_h, kernel_w, stride_h, stride_w;
    uint32_t dilation_h, dilation_w;
    uint32_t pad_top, pad_left, pad_bottom, pad_right;
    uint32_t tile_m;
} soc_conv2d_shape;

typedef struct {
    uint32_t output_h, output_w, rows, k;
    uint32_t input_bytes, weight_bytes, output_bytes, scratch_bytes;
} soc_conv2d_layout;

int soc_conv2d_layout_int8_i32(const soc_conv2d_shape *shape,
                                  soc_conv2d_layout *layout);

/* A 1x1 stride-one unpadded HWC input is already the GEMM A matrix. Other
 * convolutions use two 64-byte-aligned im2col tiles so the CPU can prepare
 * the next tile while the NPU consumes the current one. */
int soc_conv2d_direct_hwc(const soc_conv2d_shape *shape);
int soc_conv2d_workspace_bytes(const soc_conv2d_shape *shape,
                                 const soc_conv2d_layout *layout,
                                 uint32_t *stride, uint32_t *bytes);

void soc_im2col_int8_tile(const volatile int8_t *input,
                            volatile int8_t *scratch,
                            const soc_conv2d_shape *shape,
                            const soc_conv2d_layout *layout,
                            uint32_t first_row, uint32_t row_count);

#endif
