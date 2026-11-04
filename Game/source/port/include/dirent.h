// [ARCH] 兼容目录项声明对应当前的空目录枚举实现。
// [ARCH] 不表示有真实磁盘目录或持久文件系统。
#ifndef SOC_DIRENT_H
#define SOC_DIRENT_H
#include <stddef.h>
struct dirent {char d_name[64];};
typedef struct {int unused;} DIR;
int scandir(const char*,struct dirent***,int(*)(const struct dirent*),int(*)(const struct dirent**,const struct dirent**));
int alphasort(const struct dirent**,const struct dirent**);
#endif
