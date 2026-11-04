// Independently written ChaCha20 block known-answer test; no upstream code copied.
#include <stdint.h>
#include "crypto_vectors.h"
#ifdef HOST_REFERENCE
#include <stdio.h>
static void emit(char c){putchar(c);}
#else
static void emit(char c){volatile uint32_t*p=(volatile uint32_t*)0x10000000u;while(*p&0x80000000u){}*p=(uint8_t)c;}
#endif
static void text(const char*s){while(*s)emit(*s++);}
static uint32_t rot(uint32_t v,unsigned n){return (v<<n)|(v>>(32-n));}
static void quarter(uint32_t*x,unsigned a,unsigned b,unsigned c,unsigned d){
 x[a]+=x[b];x[d]=rot(x[d]^x[a],16);
 x[c]+=x[d];x[b]=rot(x[b]^x[c],12);
 x[a]+=x[b];x[d]=rot(x[d]^x[a],8);
 x[c]+=x[d];x[b]=rot(x[b]^x[c],7);
}
__attribute__((noinline)) static void block(const uint32_t*in,uint32_t*out){
 for(unsigned i=0;i<16;i++)out[i]=in[i];
 for(unsigned i=0;i<10;i++){
 quarter(out,0,4,8,12);quarter(out,1,5,9,13);quarter(out,2,6,10,14);quarter(out,3,7,11,15);
 quarter(out,0,5,10,15);quarter(out,1,6,11,12);quarter(out,2,7,8,13);quarter(out,3,4,9,14);
 }
 for(unsigned i=0;i<16;i++)out[i]+=in[i];
}
static void hexblock(const uint32_t*x){const char*digits="0123456789abcdef";
 for(unsigned i=0;i<16;i++)for(unsigned b=0;b<4;b++){unsigned v=(x[i]>>(8*b))&255;emit(digits[v>>4]);emit(digits[v&15]);}emit('\n');}
int main(void){uint32_t output[16];unsigned failures=0;
 for(unsigned n=0;n<32;n++){
 block(inputs[n],output);
 for(unsigned w=0;w<16;w++)if(output[w]!=expected[n][w])failures++;
 if(n==0){text("CRYPTO_VECTOR0=");hexblock(output);}
 if(n==31){text("CRYPTO_VECTOR31=");hexblock(output);}
 }
 if(failures){text("CRYPTO_FAIL\n");return 1;}
 text("CRYPTO_PASS blocks=32 bytes_compared=2048\n");return 0;
}
