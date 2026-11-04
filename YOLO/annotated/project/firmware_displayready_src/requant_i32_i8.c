// 架构导读：requant_i32_i8。
// INT32 到 INT8 的软件重量化参考/保留路径，约束舍入与饱和。
#include "requant_i32_i8.h"

/* The packaged YOLO graph has at most 256 channels. These arrays live in
 * DTCM, so each channel's parameters are fetched from DDR once per layer.
 * Larger standalone requests retain the same arithmetic via a fallback.
 */
#define RQ_CACHED_CHANNELS 256u
static int32_t cached_bias[RQ_CACHED_CHANNELS];
static int32_t cached_multiplier[RQ_CACHED_CHANNELS];
static uint32_t cached_shift[RQ_CACHED_CHANNELS];

// 服务函数 rounded_shift。
// 接口参数：int64_t value,uint32_t shift,uint32_t mode；返回值及副作用由下列函数体定义。
// 参数入口：value, shift, mode；类型、指针限定及返回约定沿用下列声明。
static int64_t rounded_shift(int64_t value,uint32_t shift,uint32_t mode) {
    // 控制边界：!shift；仅在该条件成立时进入本分支。
    if(!shift) return value;
    uint64_t magnitude=(uint64_t)(value<0?-value:value);
    uint64_t quotient=magnitude>>shift;
    uint64_t remainder=magnitude&((1ull<<shift)-1ull);
    uint64_t half=1ull<<(shift-1u);
    // 控制边界：mode==SOC_RQ_FLOOR；仅在该条件成立时进入本分支。
    if(mode==SOC_RQ_FLOOR) {
        // 控制边界：value<0 && remainder；仅在该条件成立时进入本分支。
        if(value<0 && remainder) quotient++;
    // 控制边界：mode==SOC_RQ_NEAREST_AWAY；仅在该条件成立时进入本分支。
    } else if(mode==SOC_RQ_NEAREST_AWAY) {
        // 控制边界：remainder>=half；仅在该条件成立时进入本分支。
        if(remainder>=half) quotient++;
    } else {
        // 控制边界：remainder>half || (remainder==half && (quotient&1u))；仅在该条件成立时进入本分支。
        if(remainder>half || (remainder==half && (quotient&1u))) quotient++;
    }
    // 返回当前检查/运算结果 value<0?-(int64_t)quotient:(int64_t)quotient，由调用者解释其状态或数值。
    return value<0?-(int64_t)quotient:(int64_t)quotient;
}

// 服务函数 requant_core。
// 接口参数：const volatile int32_t *input,；返回值及副作用由下列函数体定义。
// 参数入口：volatile, int8_t, bias, multiplier, shift, elements, channels；类型、指针限定及返回约定沿用下列声明。
static uint32_t requant_core(const volatile int32_t *input,
                             volatile int8_t *output,
                             const volatile int32_t *bias,
                             const volatile int32_t *multiplier,
                             const volatile uint32_t *shift,
                             uint32_t elements,uint32_t channels,
                             int32_t output_zero_point,
                             int32_t clamp_min,int32_t clamp_max,
                             uint32_t mode,uint32_t acc_abs_bound,
                             uint32_t *failed_index) {
    // 控制边界：failed_index；仅在该条件成立时进入本分支。
    if(failed_index) *failed_index=UINT32_MAX;
    // 控制边界：!input || !output || !bias || !multiplier || !shift || !failed_index ||；仅在该条件成立时进入本分支。
    if(!input || !output || !bias || !multiplier || !shift || !failed_index ||
       !elements || !channels || elements%channels || mode>SOC_RQ_NEAREST_EVEN ||
       output_zero_point<-128 || output_zero_point>127 ||
       clamp_min<-128 || clamp_max>127 || clamp_min>clamp_max)
        // 返回当前检查/运算结果 SOC_RQ_BAD_PARAMS，由调用者解释其状态或数值。
        return SOC_RQ_BAD_PARAMS;
    uint32_t cache_parameters=channels<=RQ_CACHED_CHANNELS;
    uint32_t skip_preflight=acc_abs_bound && acc_abs_bound<=INT32_MAX;
    // 迭代边界：uint32_t c=0;c<channels;c++；地址和计数随循环体中的原始更新前进。
    for(uint32_t c=0;c<channels;c++) {
        int32_t b=bias[c],m=multiplier[c];
        uint32_t s=shift[c];
        // 控制边界：m<0 || s>62u；仅在该条件成立时进入本分支。
        if(m<0 || s>62u) {
            *failed_index=c;
            // 返回当前检查/运算结果 SOC_RQ_BAD_PARAMS，由调用者解释其状态或数值。
            return SOC_RQ_BAD_PARAMS;
        }
        // 控制边界：cache_parameters；仅在该条件成立时进入本分支。
        if(cache_parameters) {
            cached_bias[c]=b;
            cached_multiplier[c]=m;
            cached_shift[c]=s;
        }
        // 控制边界：(int64_t)acc_abs_bound+(b<0?-(int64_t)b:(int64_t)b)>INT32_MAX；仅在该条件成立时进入本分支。
        if((int64_t)acc_abs_bound+(b<0?-(int64_t)b:(int64_t)b)>INT32_MAX)
            skip_preflight=0u;
    }
    // 控制边界：!skip_preflight；仅在该条件成立时进入本分支。
    if(!skip_preflight) {
        // 迭代边界：uint32_t pixel=0,index=0;pixel<elements/channels;pixel++；地址和计数随循环体中的原始更新前进。
        for(uint32_t pixel=0,index=0;pixel<elements/channels;pixel++) {
            // 迭代边界：uint32_t c=0;c<channels;c++,index++；地址和计数随循环体中的原始更新前进。
            for(uint32_t c=0;c<channels;c++,index++) {
                int32_t b=cache_parameters?cached_bias[c]:bias[c];
                int64_t sum=(int64_t)input[index]+(int64_t)b;
                // 控制边界：sum<INT32_MIN || sum>INT32_MAX；仅在该条件成立时进入本分支。
                if(sum<INT32_MIN || sum>INT32_MAX) {
                    *failed_index=index;
                    // 返回当前检查/运算结果 SOC_RQ_BIAS_OVERFLOW，由调用者解释其状态或数值。
                    return SOC_RQ_BIAS_OVERFLOW;
                }
            }
        }
    }
    // 迭代边界：uint32_t pixel=0,index=0;pixel<elements/channels;pixel++；地址和计数随循环体中的原始更新前进。
    for(uint32_t pixel=0,index=0;pixel<elements/channels;pixel++) {
        // 迭代边界：uint32_t c=0;c<channels;c++,index++；地址和计数随循环体中的原始更新前进。
        for(uint32_t c=0;c<channels;c++,index++) {
            int32_t b=cache_parameters?cached_bias[c]:bias[c];
            int32_t m=cache_parameters?cached_multiplier[c]:multiplier[c];
            uint32_t s=cache_parameters?cached_shift[c]:shift[c];
            int32_t sum=input[index]+b; /* Preflight proved signed INT32 range. */
            int64_t product=(int64_t)sum*(int64_t)m;
            int64_t value=rounded_shift(product,s,mode)+output_zero_point;
            // 控制边界：value<clamp_min；仅在该条件成立时进入本分支。
            if(value<clamp_min) value=clamp_min;
            // 控制边界：value>clamp_max；仅在该条件成立时进入本分支。
            if(value>clamp_max) value=clamp_max;
            output[index]=(int8_t)value;
        }
    }
    // 返回当前检查/运算结果 SOC_RQ_OK，由调用者解释其状态或数值。
    return SOC_RQ_OK;
}

// 服务函数 soc_requant_i32_i8。
// 接口参数：const volatile int32_t *input,；返回值及副作用由下列函数体定义。
// 参数入口：volatile, int8_t, bias, multiplier, shift, elements, channels；类型、指针限定及返回约定沿用下列声明。
uint32_t soc_requant_i32_i8(const volatile int32_t *input,
                              volatile int8_t *output,
                              const volatile int32_t *bias,
                              const volatile int32_t *multiplier,
                              const volatile uint32_t *shift,
                              uint32_t elements,uint32_t channels,
                              int32_t output_zero_point,
                              int32_t clamp_min,int32_t clamp_max,
                              uint32_t mode,uint32_t *failed_index) {
    // 返回当前检查/运算结果 requant_core(input,output,bias,multiplier,shift,elements,channels,，由调用者解释其状态或数值。
    return requant_core(input,output,bias,multiplier,shift,elements,channels,
                        output_zero_point,clamp_min,clamp_max,mode,0u,failed_index);
}

// 服务函数 soc_requant_i32_i8_from_conv。
// 接口参数：const volatile int32_t *input,；返回值及副作用由下列函数体定义。
// 参数入口：volatile, int8_t, bias, multiplier, shift, elements, channels；类型、指针限定及返回约定沿用下列声明。
uint32_t soc_requant_i32_i8_from_conv(const volatile int32_t *input,
                                        volatile int8_t *output,
                                        const volatile int32_t *bias,
                                        const volatile int32_t *multiplier,
                                        const volatile uint32_t *shift,
                                        uint32_t elements,uint32_t channels,
                                        int32_t output_zero_point,
                                        int32_t clamp_min,int32_t clamp_max,
                                        uint32_t mode,uint32_t acc_abs_bound,
                                        uint32_t *failed_index) {
    // 返回当前检查/运算结果 requant_core(input,output,bias,multiplier,shift,elements,channels,，由调用者解释其状态或数值。
    return requant_core(input,output,bias,multiplier,shift,elements,channels,
                        output_zero_point,clamp_min,clamp_max,mode,
                        acc_abs_bound,failed_index);
}
