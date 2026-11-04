#include "conv2d_int8.h"

static int multiply(uint32_t a, uint32_t b, uint32_t *product) {
    if(a && b>UINT32_MAX/a) return 0;
    *product=a*b;
    return 1;
}

int soc_conv2d_layout_int8_i32(const soc_conv2d_shape *s,
                                  soc_conv2d_layout *l) {
    uint32_t padded_h,padded_w,kernel_h,kernel_w,temp;
    if(!s || !l || !s->input_h || !s->input_w || !s->input_c ||
       !s->output_c || !s->kernel_h || !s->kernel_w ||
       !s->stride_h || !s->stride_w || !s->dilation_h || !s->dilation_w ||
       !s->tile_m || s->tile_m>65535u || s->output_c>65535u)
        return 0;
    if(s->input_h>UINT32_MAX-s->pad_top ||
       s->input_h+s->pad_top>UINT32_MAX-s->pad_bottom ||
       s->input_w>UINT32_MAX-s->pad_left ||
       s->input_w+s->pad_left>UINT32_MAX-s->pad_right)
        return 0;
    padded_h=s->input_h+s->pad_top+s->pad_bottom;
    padded_w=s->input_w+s->pad_left+s->pad_right;
    if(!multiply(s->kernel_h-1u,s->dilation_h,&temp) || temp==UINT32_MAX)
        return 0;
    kernel_h=temp+1u;
    if(!multiply(s->kernel_w-1u,s->dilation_w,&temp) || temp==UINT32_MAX)
        return 0;
    kernel_w=temp+1u;
    if(padded_h<kernel_h || padded_w<kernel_w) return 0;
    l->output_h=(padded_h-kernel_h)/s->stride_h+1u;
    l->output_w=(padded_w-kernel_w)/s->stride_w+1u;
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

int soc_conv2d_direct_hwc(const soc_conv2d_shape *s) {
    return s && s->kernel_h==1u && s->kernel_w==1u &&
           s->stride_h==1u && s->stride_w==1u &&
           !s->pad_top && !s->pad_left && !s->pad_bottom && !s->pad_right;
}

int soc_conv2d_workspace_bytes(const soc_conv2d_shape *s,
                                 const soc_conv2d_layout *l,
                                 uint32_t *stride, uint32_t *bytes) {
    if(!s || !l || !stride || !bytes) return 0;
    if(soc_conv2d_direct_hwc(s)) {
        *stride=0u;*bytes=0u;
        return 1;
    }
    if(l->scratch_bytes>UINT32_MAX-63u) return 0;
    *stride=(l->scratch_bytes+63u)&~63u;
    if(*stride>UINT32_MAX/2u) return 0;
    *bytes=*stride*2u;
    return 1;
}

void soc_im2col_int8_tile(const volatile int8_t *input,
                            volatile int8_t *scratch,
                            const soc_conv2d_shape *s,
                            const soc_conv2d_layout *l,
                            uint32_t first_row,uint32_t row_count) {
    for(uint32_t row=0;row<row_count;row++) {
        uint32_t position=first_row+row;
        uint32_t oy=position/l->output_w,ox=position%l->output_w;
        uint32_t target=row*l->k;
        for(uint32_t ky=0;ky<s->kernel_h;ky++) {
            uint32_t py=oy*s->stride_h+ky*s->dilation_h;
            for(uint32_t kx=0;kx<s->kernel_w;kx++) {
                uint32_t px=ox*s->stride_w+kx*s->dilation_w;
                if(py<s->pad_top || px<s->pad_left ||
                   py-s->pad_top>=s->input_h || px-s->pad_left>=s->input_w) {
                    for(uint32_t c=0;c<s->input_c;c++) scratch[target++]=0;
                } else {
                    uint32_t source=((py-s->pad_top)*s->input_w+
                                     (px-s->pad_left))*s->input_c;
                    for(uint32_t c=0;c<s->input_c;c++)
                        scratch[target++]=input[source+c];
                }
            }
        }
    }
}
