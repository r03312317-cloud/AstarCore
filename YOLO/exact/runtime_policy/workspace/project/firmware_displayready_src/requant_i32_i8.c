#include "requant_i32_i8.h"

/* The packaged YOLO graph has at most 256 channels. These arrays live in
 * DTCM, so each channel's parameters are fetched from DDR once per layer.
 * Larger standalone requests retain the same arithmetic via a fallback.
 */
#define RQ_CACHED_CHANNELS 256u
static int32_t cached_bias[RQ_CACHED_CHANNELS];
static int32_t cached_multiplier[RQ_CACHED_CHANNELS];
static uint32_t cached_shift[RQ_CACHED_CHANNELS];

static int64_t rounded_shift(int64_t value,uint32_t shift,uint32_t mode) {
    if(!shift) return value;
    uint64_t magnitude=(uint64_t)(value<0?-value:value);
    uint64_t quotient=magnitude>>shift;
    uint64_t remainder=magnitude&((1ull<<shift)-1ull);
    uint64_t half=1ull<<(shift-1u);
    if(mode==SOC_RQ_FLOOR) {
        if(value<0 && remainder) quotient++;
    } else if(mode==SOC_RQ_NEAREST_AWAY) {
        if(remainder>=half) quotient++;
    } else {
        if(remainder>half || (remainder==half && (quotient&1u))) quotient++;
    }
    return value<0?-(int64_t)quotient:(int64_t)quotient;
}

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
    if(failed_index) *failed_index=UINT32_MAX;
    if(!input || !output || !bias || !multiplier || !shift || !failed_index ||
       !elements || !channels || elements%channels || mode>SOC_RQ_NEAREST_EVEN ||
       output_zero_point<-128 || output_zero_point>127 ||
       clamp_min<-128 || clamp_max>127 || clamp_min>clamp_max)
        return SOC_RQ_BAD_PARAMS;
    uint32_t cache_parameters=channels<=RQ_CACHED_CHANNELS;
    uint32_t skip_preflight=acc_abs_bound && acc_abs_bound<=INT32_MAX;
    for(uint32_t c=0;c<channels;c++) {
        int32_t b=bias[c],m=multiplier[c];
        uint32_t s=shift[c];
        if(m<0 || s>62u) {
            *failed_index=c;
            return SOC_RQ_BAD_PARAMS;
        }
        if(cache_parameters) {
            cached_bias[c]=b;
            cached_multiplier[c]=m;
            cached_shift[c]=s;
        }
        if((int64_t)acc_abs_bound+(b<0?-(int64_t)b:(int64_t)b)>INT32_MAX)
            skip_preflight=0u;
    }
    if(!skip_preflight) {
        for(uint32_t pixel=0,index=0;pixel<elements/channels;pixel++) {
            for(uint32_t c=0;c<channels;c++,index++) {
                int32_t b=cache_parameters?cached_bias[c]:bias[c];
                int64_t sum=(int64_t)input[index]+(int64_t)b;
                if(sum<INT32_MIN || sum>INT32_MAX) {
                    *failed_index=index;
                    return SOC_RQ_BIAS_OVERFLOW;
                }
            }
        }
    }
    for(uint32_t pixel=0,index=0;pixel<elements/channels;pixel++) {
        for(uint32_t c=0;c<channels;c++,index++) {
            int32_t b=cache_parameters?cached_bias[c]:bias[c];
            int32_t m=cache_parameters?cached_multiplier[c]:multiplier[c];
            uint32_t s=cache_parameters?cached_shift[c]:shift[c];
            int32_t sum=input[index]+b; /* Preflight proved signed INT32 range. */
            int64_t product=(int64_t)sum*(int64_t)m;
            int64_t value=rounded_shift(product,s,mode)+output_zero_point;
            if(value<clamp_min) value=clamp_min;
            if(value>clamp_max) value=clamp_max;
            output[index]=(int8_t)value;
        }
    }
    return SOC_RQ_OK;
}

uint32_t soc_requant_i32_i8(const volatile int32_t *input,
                              volatile int8_t *output,
                              const volatile int32_t *bias,
                              const volatile int32_t *multiplier,
                              const volatile uint32_t *shift,
                              uint32_t elements,uint32_t channels,
                              int32_t output_zero_point,
                              int32_t clamp_min,int32_t clamp_max,
                              uint32_t mode,uint32_t *failed_index) {
    return requant_core(input,output,bias,multiplier,shift,elements,channels,
                        output_zero_point,clamp_min,clamp_max,mode,0u,failed_index);
}

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
    return requant_core(input,output,bias,multiplier,shift,elements,channels,
                        output_zero_point,clamp_min,clamp_max,mode,
                        acc_abs_bound,failed_index);
}
