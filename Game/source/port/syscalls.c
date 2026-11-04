// [ARCH] newlib 系统调用边界把标准输出转到 UART。
// [ARCH] _sbrk 只在固定 DDR 堆区内增长或回退。
// [ARCH] 文件句柄委派给有界 RAM 接口，不需要宿主操作系统。
// [ARCH] 时间由真实机器周期换算，不使用 PC 墙钟。
// [ARCH] 不支持的进程/文件操作返回错误。
// [ARCH] _exit 打印 MARIO_EXIT，验收视为程序未持续运行。
// [ARCH] 目录枚举为空实现，不能宣称完整 POSIX 文件系统。
#include "soc_port.h"
#include <sys/stat.h>
#include <sys/time.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include <unistd.h>
#include "dirent.h"
static char *empty_environment[]={NULL};
char **environ=empty_environment;
void *_sbrk(ptrdiff_t increment) {
    static uintptr_t brk=SOC_HEAP_BASE;uintptr_t old=brk;
    if(increment<0){uintptr_t n=(uintptr_t)(-(increment+1))+1;if(n>brk-SOC_HEAP_BASE){errno=ENOMEM;return (void*)-1;}brk-=n;}
    else {if((uintptr_t)increment>SOC_HEAP_LIMIT-brk){errno=ENOMEM;return (void*)-1;}brk+=(uintptr_t)increment;}
    return (void*)old;
}
int _open(const char*p,int flags,...){return soc_fs_open(p,flags);}
int _close(int fd){return fd<3?0:soc_fs_close(fd);}
int _read(int fd,void*b,size_t n){if(fd==0){int c=soc_uart_getc(1000);if(c<0||!n)return 0;*(char*)b=(char)c;return 1;}return soc_fs_read(fd,b,n);}
int _write(int fd,const void*b,size_t n){if(fd==1||fd==2){const char*p=b;for(size_t i=0;i<n;i++)soc_uart_putc(p[i]);return (int)n;}return soc_fs_write(fd,b,n);}
off_t _lseek(int fd,off_t off,int whence){return (off_t)soc_fs_seek(fd,(long)off,whence);}
int _fstat(int fd,struct stat*s){memset(s,0,sizeof *s);if(fd<3){s->st_mode=S_IFCHR;return 0;}long n=soc_fs_size(fd);if(n<0)return -1;s->st_mode=S_IFREG|0444;s->st_size=n;return 0;}
int _stat(const char*p,struct stat*s){int fd=soc_fs_open(p,O_RDONLY);if(fd<0)return -1;int r=_fstat(fd,s);soc_fs_close(fd);return r;}
int _isatty(int fd){return fd==0||fd==1||fd==2;}
// [ARCH] 从 100 MHz 机器周期换算微秒。
// [ARCH] 64 位结果先保证一致读取，再进行单位转换。
// [ARCH] 主机下载耗时不参与这个运行时钟。
int _gettimeofday(struct timeval*tv,void*tz){(void)tz;uint64_t us=soc_cycles()/100;tv->tv_sec=(time_t)(us/1000000);tv->tv_usec=(long)(us%1000000);return 0;}
int _getpid(void){return 1;}
int _kill(int pid,int sig){(void)pid;(void)sig;errno=ENOSYS;return -1;}
// [ARCH] 输出明确的异常退出标记并停留。
// [ARCH] 启动工具把它作为未持续运行处理。
// [ARCH] 不能把程序退出当作演示下载成功。
void _exit(int code){(void)code;soc_uart_puts("MARIO_EXIT\n");for(;;){}}
int _unlink(const char*p){(void)p;errno=EROFS;return -1;}
int _link(const char*a,const char*b){(void)a;(void)b;errno=EROFS;return -1;}
char *getcwd(char *buf,size_t n){if(!buf||n<2){errno=ERANGE;return NULL;}strcpy(buf,".");return buf;}
int chdir(const char*p){if(!strcmp(p,".")||!strcmp(p,"./"))return 0;errno=ENOENT;return -1;}
int access(const char*p,int mode){(void)mode;int fd=soc_fs_open(p,O_RDONLY);if(fd<0)return -1;soc_fs_close(fd);return 0;}
/* Resource names are normalized at mount and opens are case insensitive, so
 * SDLPAL's optional filesystem case-search fallback never needs enumeration. */
int scandir(const char*p,struct dirent***v,int(*filter)(const struct dirent*),int(*compare)(const struct dirent**,const struct dirent**)) {(void)p;(void)filter;(void)compare;*v=NULL;return 0;}
int alphasort(const struct dirent**a,const struct dirent**b){return strcmp((*a)->d_name,(*b)->d_name);}
void _init(void){} void _fini(void){}
