#ifndef SOC_DIRENT_H
#define SOC_DIRENT_H
#include <stddef.h>
struct dirent {char d_name[64];};
typedef struct {int unused;} DIR;
int scandir(const char*,struct dirent***,int(*)(const struct dirent*),int(*)(const struct dirent**,const struct dirent**));
int alphasort(const struct dirent**,const struct dirent**);
#endif
