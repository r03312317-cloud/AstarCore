// 架构导读：conv2d_int8。
// 卷积参数与数据布局检查及保留的软件参考运算。
#include "conv2d_int8.h"

// 服务函数 multiply。
// 接口参数：uint32_t a, uint32_t b, uint32_t *product；返回值及副作用由下列函数体定义。
// 参数入口：a, b, product；类型、指针限定及返回约定沿用下列声明。
static int multiply(uint32_t a, uint32_t b, uint32_t *product) {
    // 控制边界：a && b>UINT32_MAX/a；仅在该条件成立时进入本分支。
    if(a && b>UINT32_MAX/a) return 0;
    *product=a*b;
    // 返回当前检查/运算结果 1，由调用者解释其状态或数值。
    return 1;
}

// 服务函数 soc_conv2d_layout_int8_i32。
// 接口参数：const soc_conv2d_shape *s,；返回值及副作用由下列函数体定义。
// 参数入口：s, l；类型、指针限定及返回约定沿用下列声明。
int soc_conv2d_layout_int8_i32(const soc_conv2d_shape *s,
                                  soc_conv2d_layout *l) {
    uint32_t padded_h,padded_w,kernel_h,kernel_w,temp;
    // 控制边界：!s || !l || !s->input_h || !s->input_w || !s->input_c ||；仅在该条件成立时进入本分支。
    if(!s || !l || !s->input_h || !s->input_w || !s->input_c ||
       !s->output_c || !s->kernel_h || !s->kernel_w ||
       !s->stride_h || !s->stride_w || !s->dilation_h || !s->dilation_w ||
       !s->tile_m || s->tile_m>65535u || s->output_c>65535u)
        // 返回当前检查/运算结果 0，由调用者解释其状态或数值。
        return 0;
    // 控制边界：s->input_h>UINT32_MAX-s->pad_top ||；仅在该条件成立时进入本分支。
    if(s->input_h>UINT32_MAX-s->pad_top ||
       s->input_h+s->pad_top>UINT32_MAX-s->pad_bottom ||
       s->input_w>UINT32_MAX-s->pad_left ||
       s->input_w+s->pad_left>UINT32_MAX-s->pad_right)
        return 0;
    padded_h=s->input_h+s->pad_top+s->pad_bottom;
    padded_w=s->input_w+s->pad_left+s->pad_right;
    // 控制边界：!multiply(s->kernel_h-1u,s->dilation_h,&temp) || temp==UINT32_MAX；仅在该条件成立时进入本分支。
    if(!multiply(s->kernel_h-1u,s->dilation_h,&temp) || temp==UINT32_MAX)
        return 0;
    kernel_h=temp+1u;
    // 控制边界：!multiply(s->kernel_w-1u,s->dilation_w,&temp) || temp==UINT32_MAX；仅在该条件成立时进入本分支。
    if(!multiply(s->kernel_w-1u,s->dilation_w,&temp) || temp==UINT32_MAX)
        return 0;
    kernel_w=temp+1u;
    // 控制边界：padded_h<kernel_h || padded_w<kernel_w；仅在该条件成立时进入本分支。
    if(padded_h<kernel_h || padded_w<kernel_w) return 0;
    l->output_h=(padded_h-kernel_h)/s->stride_h+1u;
    l->output_w=(padded_w-kernel_w)/s->stride_w+1u;
    // 控制边界：!multiply(l->output_h,l->output_w,&l->rows) ||；仅在该条件成立时进入本分支。
    if(!multiply(l->output_h,l->output_w,&l->rows) ||
       !multiply(s->kernel_h,s->kernel_w,&temp) ||
       !multiply(temp,s->input_c,&l->k) || !l->k || l->k>65535u ||
       !multiply(s->input_h,s->input_w,&temp) ||
       !multiply(temp,s->input_c,&l->input_bytes) ||
       !multiply(l->k,s->output_c,&l->weight_bytes) ||
       !multiply(l->rows,s->output_c,&temp) ||
       !multiply(temp,4u,&l->output_bytes) ||
       !multiply(s->tile_m,l->k,&l->scratch_bytes)) return 0;
    return 1;
}

// 服务函数 soc_conv2d_direct_hwc。
// 接口参数：const soc_conv2d_shape *s；返回值及副作用由下列函数体定义。
// 参数入口：s；类型、指针限定及返回约定沿用下列声明。
int soc_conv2d_direct_hwc(const soc_conv2d_shape *s) {
    return s && s->kernel_h==1u && s->kernel_w==1u &&
           s->stride_h==1u && s->stride_w==1u &&
           !s->pad_top && !s->pad_left && !s->pad_bottom && !s->pad_right;
}

// 服务函数 soc_conv2d_workspace_bytes。
// 接口参数：const soc_conv2d_shape *s,；返回值及副作用由下列函数体定义。
// 参数入口：s, l, stride, bytes；类型、指针限定及返回约定沿用下列声明。
int soc_conv2d_workspace_bytes(const soc_conv2d_shape *s,
                                 const soc_conv2d_layout *l,
                                 uint32_t *stride, uint32_t *bytes) {
    // 控制边界：!s || !l || !stride || !bytes；仅在该条件成立时进入本分支。
    if(!s || !l || !stride || !bytes) return 0;
    // 控制边界：soc_conv2d_direct_hwc(s)；仅在该条件成立时进入本分支。
    if(soc_conv2d_direct_hwc(s)) {
        *stride=0u;*bytes=0u;
        return 1;
    }
    // 控制边界：l->scratch_bytes>UINT32_MAX-63u；仅在该条件成立时进入本分支。
    if(l->scratch_bytes>UINT32_MAX-63u) return 0;
    *stride=(l->scratch_bytes+63u)&~63u;
    // 控制边界：*stride>UINT32_MAX/2u；仅在该条件成立时进入本分支。
    if(*stride>UINT32_MAX/2u) return 0;
    *bytes=*stride*2u;
    return 1;
}

// 服务函数 soc_im2col_int8_tile。
// 接口参数：const volatile int8_t *input,；返回值及副作用由下列函数体定义。
// 参数入口：int8_t, scratch, s, l, first_row, row_count；类型、指针限定及返回约定沿用下列声明。
void soc_im2col_int8_tile(const volatile int8_t *input,
                            volatile int8_t *scratch,
                            const soc_conv2d_shape *s,
                            const soc_conv2d_layout *l,
                            uint32_t first_row,uint32_t row_count) {
    // 迭代边界：uint32_t row=0;row<row_count;row++；地址和计数随循环体中的原始更新前进。
    for(uint32_t row=0;row<row_count;row++) {
        uint32_t position=first_row+row;
        uint32_t oy=position/l->output_w,ox=position%l->output_w;
        uint32_t target=row*l->k;
        // 迭代边界：uint32_t ky=0;ky<s->kernel_h;ky++；地址和计数随循环体中的原始更新前进。
        for(uint32_t ky=0;ky<s->kernel_h;ky++) {
            uint32_t py=oy*s->stride_h+ky*s->dilation_h;
            // 迭代边界：uint32_t kx=0;kx<s->kernel_w;kx++；地址和计数随循环体中的原始更新前进。
            for(uint32_t kx=0;kx<s->kernel_w;kx++) {
                uint32_t px=ox*s->stride_w+kx*s->dilation_w;
                // 控制边界：py<s->pad_top || px<s->pad_left ||；仅在该条件成立时进入本分支。
                if(py<s->pad_top || px<s->pad_left ||
                   py-s->pad_top>=s->input_h || px-s->pad_left>=s->input_w) {
                    // 迭代边界：uint32_t c=0;c<s->input_c;c++；地址和计数随循环体中的原始更新前进。
                    for(uint32_t c=0;c<s->input_c;c++) scratch[target++]=0;
                } else {
                    uint32_t source=((py-s->pad_top)*s->input_w+
                                     (px-s->pad_left))*s->input_c;
                    // 迭代边界：uint32_t c=0;c<s->input_c;c++；地址和计数随循环体中的原始更新前进。
                    for(uint32_t c=0;c<s->input_c;c++)
                        scratch[target++]=input[source+c];
                }
            }
        }
    }
}
