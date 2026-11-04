#ifndef SOC_KLIB_MACROS_H
#define SOC_KLIB_MACROS_H
#include <stdio.h>
#include <stdlib.h>
#define CONCAT_INNER(a,b) a##b
#define CONCAT(a,b) CONCAT_INNER(a,b)
#define STRING_INNER(x) #x
#define TOSTRING(x) STRING_INNER(x)
#define panic_on(cond,message) do {if(cond){fprintf(stderr,"MARIO_PANIC: %s\n",message);abort();}}while(0)
#endif
