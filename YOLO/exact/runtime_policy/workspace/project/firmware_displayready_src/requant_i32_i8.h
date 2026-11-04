#ifndef SOC_REQUANT_I32_I8_H
#define SOC_REQUANT_I32_I8_H

#include <stdint.h>

#define SOC_REQUANT_ID 0x31515452u /* "RTQ1" as little-endian bytes */
enum { SOC_RQ_FLOOR=0, SOC_RQ_NEAREST_AWAY=1,
       SOC_RQ_NEAREST_EVEN=2 };
enum { SOC_RQ_OK=0, SOC_RQ_BAD_PARAMS=1,
       SOC_RQ_BIAS_OVERFLOW=2 };

/* HWC-flat INT32 accumulators -> INT8 activations, channel index i % channels.
 * Per channel: sum = acc + bias, constrained to signed INT32; then
 * q = round(sum * nonnegative_multiplier / 2^shift) + output_zero_point;
 * finally clamp to [clamp_min,clamp_max] within signed INT8. The rounding
 * mode is explicit. A preflight pass prevents partial output on bad params or
 * bias overflow. This is an arithmetic contract, not an assumed YOLO scale.
 */
uint32_t soc_requant_i32_i8(const volatile int32_t *input,
                              volatile int8_t *output,
                              const volatile int32_t *bias,
                              const volatile int32_t *multiplier,
                              const volatile uint32_t *shift,
                              uint32_t elements,uint32_t channels,
                              int32_t output_zero_point,
                              int32_t clamp_min,int32_t clamp_max,
                              uint32_t rounding_mode,
                              uint32_t *failed_index);

/* Only for an accumulator just written by a successful signed-INT8 Conv
 * descriptor with identical output address/count. The caller must prove
 * abs(acc) <= acc_abs_bound from K*128*128 and prevent concurrent writes.
 * If acc_abs_bound + any bias is too large, the regular preflight runs.
 */
uint32_t soc_requant_i32_i8_from_conv(const volatile int32_t *input,
                                        volatile int8_t *output,
                                        const volatile int32_t *bias,
                                        const volatile int32_t *multiplier,
                                        const volatile uint32_t *shift,
                                        uint32_t elements,uint32_t channels,
                                        int32_t output_zero_point,
                                        int32_t clamp_min,int32_t clamp_max,
                                        uint32_t rounding_mode,
                                        uint32_t acc_abs_bound,
                                        uint32_t *failed_index);

#endif
