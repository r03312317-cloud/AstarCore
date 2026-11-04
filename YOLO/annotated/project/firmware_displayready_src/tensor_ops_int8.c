// 架构导读：tensor_ops_int8。
// 共享张量算子的布局检查和软件参考操作。
#include "tensor_ops_int8.h"

#define MAX_TENSOR_BYTES 0x04000000ull

// 服务函数 valid_bytes。
// 接口参数：uint64_t count；返回值及副作用由下列函数体定义。
// 参数入口：count；类型、指针限定及返回约定沿用下列声明。
static int valid_bytes(uint64_t count) {
    return count>0 && count<=MAX_TENSOR_BYTES;
}

// 服务函数 soc_tensor_layout_int8。
// 接口参数：const soc_tensor_shape *s,；返回值及副作用由下列函数体定义。
// 参数入口：s, l；类型、指针限定及返回约定沿用下列声明。
int soc_tensor_layout_int8(const soc_tensor_shape *s,
                            soc_tensor_layout *l) {
    // 控制边界：!s || !l || !s->input_h || !s->input_w || !s->input_c ||；仅在该条件成立时进入本分支。
    if(!s || !l || !s->input_h || !s->input_w || !s->input_c ||
       s->input_h>4096u || s->input_w>4096u || s->input_c>65535u || s->param)
        return 0;
    uint64_t input=(uint64_t)s->input_h*s->input_w*s->input_c;
    // 控制边界：!valid_bytes(input)；仅在该条件成立时进入本分支。
    if(!valid_bytes(input)) return 0;
    uint64_t output=0,aux=0;
    uint32_t oh=0,ow=0,oc=0;
    // 控制边界：s->kind==SOC_TOP_POOL；仅在该条件成立时进入本分支。
    if(s->kind==SOC_TOP_POOL) {
        // 控制边界：s->aux_c || !s->kernel_h || !s->kernel_w ||；仅在该条件成立时进入本分支。
        if(s->aux_c || !s->kernel_h || !s->kernel_w ||
           s->kernel_h>7u || s->kernel_w>7u ||
           !s->stride_h || !s->stride_w ||
           s->stride_h>4u || s->stride_w>4u ||
           s->pad_top>7u || s->pad_left>7u ||
           s->pad_bottom>7u || s->pad_right>7u) return 0;
        uint32_t ph=s->input_h+s->pad_top+s->pad_bottom;
        uint32_t pw=s->input_w+s->pad_left+s->pad_right;
        // 控制边界：ph<s->kernel_h || pw<s->kernel_w；仅在该条件成立时进入本分支。
        if(ph<s->kernel_h || pw<s->kernel_w) return 0;
        oh=(ph-s->kernel_h)/s->stride_h+1u;
        ow=(pw-s->kernel_w)/s->stride_w+1u;
        oc=s->input_c;
    // 控制边界：s->kind==SOC_TOP_UPSAMPLE；仅在该条件成立时进入本分支。
    } else if(s->kind==SOC_TOP_UPSAMPLE) {
        // 控制边界：s->aux_c || s->kernel_h || s->kernel_w ||；仅在该条件成立时进入本分支。
        if(s->aux_c || s->kernel_h || s->kernel_w ||
           !s->stride_h || !s->stride_w ||
           s->stride_h>4u || s->stride_w>4u ||
           s->pad_top || s->pad_left || s->pad_bottom || s->pad_right)
            return 0;
        // 控制边界：(uint64_t)s->input_h*s->stride_h>4096u ||；仅在该条件成立时进入本分支。
        if((uint64_t)s->input_h*s->stride_h>4096u ||
           (uint64_t)s->input_w*s->stride_w>4096u) return 0;
        oh=s->input_h*s->stride_h;ow=s->input_w*s->stride_w;oc=s->input_c;
    // 控制边界：s->kind==SOC_TOP_CONCAT；仅在该条件成立时进入本分支。
    } else if(s->kind==SOC_TOP_CONCAT) {
        // 控制边界：!s->aux_c || s->aux_c>65535u-s->input_c ||；仅在该条件成立时进入本分支。
        if(!s->aux_c || s->aux_c>65535u-s->input_c ||
           s->kernel_h || s->kernel_w || s->stride_h || s->stride_w ||
           s->pad_top || s->pad_left || s->pad_bottom || s->pad_right)
            return 0;
        oh=s->input_h;ow=s->input_w;oc=s->input_c+s->aux_c;
        aux=(uint64_t)oh*ow*s->aux_c;
    // 控制边界：s->kind==SOC_TOP_LUT || s->kind==SOC_TOP_ADD；仅在该条件成立时进入本分支。
    } else if(s->kind==SOC_TOP_LUT || s->kind==SOC_TOP_ADD) {
        // 控制边界：s->aux_c || s->kernel_h || s->kernel_w ||；仅在该条件成立时进入本分支。
        if(s->aux_c || s->kernel_h || s->kernel_w ||
           s->stride_h || s->stride_w ||
           s->pad_top || s->pad_left || s->pad_bottom || s->pad_right)
            return 0;
        oh=s->input_h;ow=s->input_w;oc=s->input_c;
        aux=s->kind==SOC_TOP_LUT?256u:input;
    } else return 0;
    output=(uint64_t)oh*ow*oc;
    // 控制边界：!valid_bytes(output) || (aux && !valid_bytes(aux))；仅在该条件成立时进入本分支。
    if(!valid_bytes(output) || (aux && !valid_bytes(aux))) return 0;
    l->output_h=oh;l->output_w=ow;l->output_c=oc;
    l->input_bytes=(uint32_t)input;l->aux_bytes=(uint32_t)aux;
    l->output_bytes=(uint32_t)output;
    return 1;
}

// 服务函数 soc_tensor_run_int8。
// 接口参数：const volatile int8_t *input,；返回值及副作用由下列函数体定义。
// 参数入口：int8_t, aux, int8_t, s, l；类型、指针限定及返回约定沿用下列声明。
void soc_tensor_run_int8(const volatile int8_t *input,
                          const volatile int8_t *aux,
                          volatile int8_t *output,
                          const soc_tensor_shape *s,
                          const soc_tensor_layout *l) {
    // 控制边界：s->kind==SOC_TOP_POOL；仅在该条件成立时进入本分支。
    if(s->kind==SOC_TOP_POOL) {
        // 迭代边界：uint32_t oy=0;oy<l->output_h;oy++；地址和计数随循环体中的原始更新前进。
        for(uint32_t oy=0;oy<l->output_h;oy++)
            // 迭代边界：uint32_t ox=0;ox<l->output_w;ox++；地址和计数随循环体中的原始更新前进。
            for(uint32_t ox=0;ox<l->output_w;ox++)
                // 迭代边界：uint32_t c=0;c<s->input_c;c++；地址和计数随循环体中的原始更新前进。
                for(uint32_t c=0;c<s->input_c;c++) {
                    int32_t best=-128;
                    // 迭代边界：uint32_t ky=0;ky<s->kernel_h;ky++；地址和计数随循环体中的原始更新前进。
                    for(uint32_t ky=0;ky<s->kernel_h;ky++) {
                        int32_t iy=(int32_t)(oy*s->stride_h+ky)-(int32_t)s->pad_top;
                        // 控制边界：iy<0 || (uint32_t)iy>=s->input_h；仅在该条件成立时进入本分支。
                        if(iy<0 || (uint32_t)iy>=s->input_h) continue;
                        // 迭代边界：uint32_t kx=0;kx<s->kernel_w;kx++；地址和计数随循环体中的原始更新前进。
                        for(uint32_t kx=0;kx<s->kernel_w;kx++) {
                            int32_t ix=(int32_t)(ox*s->stride_w+kx)-(int32_t)s->pad_left;
                            // 控制边界：ix<0 || (uint32_t)ix>=s->input_w；仅在该条件成立时进入本分支。
                            if(ix<0 || (uint32_t)ix>=s->input_w) continue;
                            int32_t value=input[((uint32_t)iy*s->input_w+(uint32_t)ix)*s->input_c+c];
                            // 控制边界：value>best；仅在该条件成立时进入本分支。
                            if(value>best) best=value;
                        }
                    }
                    output[(oy*l->output_w+ox)*s->input_c+c]=(int8_t)best;
                }
    // 控制边界：s->kind==SOC_TOP_UPSAMPLE；仅在该条件成立时进入本分支。
    } else if(s->kind==SOC_TOP_UPSAMPLE) {
        // 迭代边界：uint32_t y=0;y<l->output_h;y++；地址和计数随循环体中的原始更新前进。
        for(uint32_t y=0;y<l->output_h;y++)
            // 迭代边界：uint32_t x=0;x<l->output_w;x++；地址和计数随循环体中的原始更新前进。
            for(uint32_t x=0;x<l->output_w;x++)
                // 迭代边界：uint32_t c=0;c<s->input_c;c++；地址和计数随循环体中的原始更新前进。
                for(uint32_t c=0;c<s->input_c;c++)
                    output[(y*l->output_w+x)*s->input_c+c]=
                        input[((y/s->stride_h)*s->input_w+x/s->stride_w)*s->input_c+c];
    // 控制边界：s->kind==SOC_TOP_CONCAT；仅在该条件成立时进入本分支。
    } else if(s->kind==SOC_TOP_CONCAT) {
        // 迭代边界：uint32_t pixel=0;pixel<s->input_h*s->input_w;pixel++；地址和计数随循环体中的原始更新前进。
        for(uint32_t pixel=0;pixel<s->input_h*s->input_w;pixel++) {
            uint32_t start=pixel*l->output_c;
            // 迭代边界：uint32_t c=0;c<s->input_c;c++；地址和计数随循环体中的原始更新前进。
            for(uint32_t c=0;c<s->input_c;c++) output[start+c]=input[pixel*s->input_c+c];
            // 迭代边界：uint32_t c=0;c<s->aux_c;c++；地址和计数随循环体中的原始更新前进。
            for(uint32_t c=0;c<s->aux_c;c++) output[start+s->input_c+c]=aux[pixel*s->aux_c+c];
        }
    // 控制边界：s->kind==SOC_TOP_LUT；仅在该条件成立时进入本分支。
    } else if(s->kind==SOC_TOP_LUT) {
        for(uint32_t i=0;i<l->input_bytes;i++) output[i]=aux[(uint8_t)input[i]];
    } else {
        for(uint32_t i=0;i<l->input_bytes;i++) {
            int32_t value=(int32_t)input[i]+(int32_t)aux[i];
            // 控制边界：value<-128；仅在该条件成立时进入本分支。
            if(value<-128) value=-128;
            // 控制边界：value>127；仅在该条件成立时进入本分支。
            if(value>127) value=127;
            output[i]=(int8_t)value;
        }
    }
}
