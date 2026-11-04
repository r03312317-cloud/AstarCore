#include <stddef.h>
void *memcpy(void *d,const void *s,size_t n){unsigned char *p=d;const unsigned char *q=s;while(n--)*p++=*q++;return d;}
void *memset(void *d,int x,size_t n){unsigned char *p=d;while(n--)*p++=(unsigned char)x;return d;}
