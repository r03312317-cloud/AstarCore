// [ARCH] 继承的有界资源接口保留编译，当前内嵌 ROM 路径不依赖挂载。
// [ARCH] ASTPAL01 挂载前验证名称、范围、重叠与 CRC。
// [ARCH] 名称归一化并拒绝目录分隔符，避免把外部路径当裸机层次。
// [ARCH] 文件数、句柄数和可写空间均有上限。
// [ARCH] 可写内容在 RAM 中，断电不提供持久存档。
// [ARCH] 全部检查通过后才替换已挂载资源表。
// [ARCH] 未使用部分可由链接垃圾回收剔除。
/* Read-only ASTPAL01 resources plus volatile, bounded .rpg saves/config/logs. */
#include "soc_port.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#define MAX_FILES 256u
#define MAX_HANDLES 32
#define MAX_WRITABLE 16
#define SAVE_LIMIT (512u*1024u)
typedef struct {char name[64];const uint8_t *data;uint8_t *writable;uint32_t size,capacity;} file_t;
typedef struct {file_t *file;uint32_t pos;int flags;} handle_t;
static file_t files[MAX_FILES+MAX_WRITABLE];
static handle_t handles[MAX_HANDLES];
static unsigned file_count,writable_count;
static uint32_t u32(const uint8_t *p) {return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
// [ARCH] 只接受有限长度、可打印且不含路径分隔符的资源名。
// [ARCH] 名称统一成小写以保持查找口径。
// [ARCH] 这是资源键，不是真实磁盘路径。
static int normalize(const char *path,char out[64]) {
    while(path[0]=='.'&&path[1]=='/')path+=2;
    size_t n=strlen(path);if(!n||n>63)return -1;
    for(size_t i=0;i<n;i++){unsigned c=(unsigned char)path[i];if(c<32||c>126||c=='/'||c=='\\'||c==':')return -1;out[i]=(char)tolower(c);}
    out[n]=0;return strcmp(out,".")==0||strcmp(out,"..")==0?-1:0;
}
// [ARCH] 在替换旧资源表前完成全部校验。
// [ARCH] 文件范围、名称、CRC 和相互重叠都参与合法性判断。
// [ARCH] 当前马里奥正常路径不依赖此兼容挂载。
int soc_fs_mount(const void *image,size_t available) {
    const uint8_t *p=image;if(available<24||memcmp(p,"ASTPAL01",8)||u32(p+8)!=1)return -1;
    uint32_t count=u32(p+12),total=u32(p+16),table_end;
    if(count>MAX_FILES||total>available||total<24||u32(p+20)!=0)return -1;
    table_end=24+80*count;if(table_end>total)return -1;
    /* Validate everything before replacing a mounted file table. */
    for(unsigned i=0;i<count;i++) {
        const uint8_t *e=p+24+i*80;char name[64];uint32_t off=u32(e+64),len=u32(e+68);
        if(!memchr(e,0,64)||normalize((const char *)e,name)||strcmp(name,(const char *)e)||u32(e+76))return -1;
        if(off<table_end||off>total||len>total-off)return -1;
        if(soc_crc32(p+off,len)!=u32(e+72))return -1;
        for(unsigned j=0;j<i;j++){const uint8_t *q=p+24+j*80;uint32_t qo=u32(q+64),ql=u32(q+68);
            if(!strcmp((const char*)e,(const char*)q)||(len&&ql&&off<qo+ql&&qo<off+len))return -1;}
    }
    for(unsigned i=0;i<file_count;i++)free(files[i].writable);
    memset(files,0,sizeof files);memset(handles,0,sizeof handles);file_count=count;writable_count=0;
    for(unsigned i=0;i<count;i++){const uint8_t *e=p+24+i*80;strcpy(files[i].name,(const char*)e);files[i].data=p+u32(e+64);files[i].size=u32(e+68);}
    return 0;
}
static file_t *find(const char *name) {for(unsigned i=0;i<file_count;i++)if(!strcmp(name,files[i].name))return files+i;return NULL;}
static int writable_name(const char *s) {size_t n=strlen(s);return (n>4&&!strcmp(s+n-4,".rpg"))||!strcmp(s,"sdlpal.cfg")||!strcmp(s,"sdlpal.log");}
static handle_t *handle(int fd) {if(fd<3||fd>=3+MAX_HANDLES||!handles[fd-3].file){errno=EBADF;return NULL;}return handles+fd-3;}
// [ARCH] 句柄、文件对象和可写缓冲分别受容量限制。
// [ARCH] 只读资源不能因带写标志就原地修改。
// [ARCH] 允许的新可写对象仍仅保存在 RAM。
int soc_fs_open(const char *path,int flags) {
    char name[64];if(normalize(path,name)){errno=EINVAL;return -1;}
    int slot=-1;for(int i=0;i<MAX_HANDLES;i++)if(!handles[i].file){slot=i;break;}
    if(slot<0){errno=EMFILE;return -1;}
    int write=(flags&O_ACCMODE)!=O_RDONLY,new_file=0;file_t *f=find(name);
    if(f&&(flags&O_CREAT)&&(flags&O_EXCL)){errno=EEXIST;return -1;}
    if(!f && !(write&&(flags&O_CREAT))){errno=ENOENT;return -1;}
    if(write&&!writable_name(name)){errno=EROFS;return -1;}
    if(!f){if(writable_count>=MAX_WRITABLE||file_count>=MAX_FILES+MAX_WRITABLE){errno=ENOSPC;return -1;}f=files+file_count;memset(f,0,sizeof *f);strcpy(f->name,name);new_file=1;}
    if(write&&!f->writable) {
        if(writable_count>=MAX_WRITABLE||f->size>SAVE_LIMIT){errno=ENOSPC;return -1;}
        uint8_t *buf=calloc(1,SAVE_LIMIT);if(!buf){errno=ENOMEM;return -1;}
        if(f->size)memcpy(buf,f->data,f->size);
        f->writable=buf;f->data=buf;f->capacity=SAVE_LIMIT;writable_count++;
    }
    if(new_file)file_count++;
    if(write&&(flags&O_TRUNC))f->size=0;
    handles[slot]=(handle_t){f,(flags&O_APPEND)?f->size:0,flags};return slot+3;
}
int soc_fs_close(int fd) {handle_t *h=handle(fd);if(!h)return -1;memset(h,0,sizeof *h);return 0;}
int soc_fs_read(int fd,void *buffer,size_t count) {handle_t*h=handle(fd);if(!h)return -1;if((h->flags&O_ACCMODE)==O_WRONLY){errno=EBADF;return -1;}
    size_t left=h->pos<h->file->size?h->file->size-h->pos:0;if(count>left)count=left;if(count)memcpy(buffer,h->file->data+h->pos,count);h->pos+=(uint32_t)count;return (int)count;}
int soc_fs_write(int fd,const void *buffer,size_t count) {handle_t*h=handle(fd);if(!h)return -1;if((h->flags&O_ACCMODE)==O_RDONLY||!h->file->writable){errno=EBADF;return -1;}
    if(h->flags&O_APPEND)h->pos=h->file->size;
    if(h->pos>h->file->capacity||count>h->file->capacity-h->pos){errno=ENOSPC;return -1;}
    if(h->pos>h->file->size)memset(h->file->writable+h->file->size,0,h->pos-h->file->size);
    if(count)memcpy(h->file->writable+h->pos,buffer,count);
    h->pos+=(uint32_t)count;if(h->pos>h->file->size)h->file->size=h->pos;return (int)count;}
long soc_fs_seek(int fd,long offset,int whence) {handle_t*h=handle(fd);if(!h)return -1;int64_t base;
    if(whence==SEEK_SET)base=0;else if(whence==SEEK_CUR)base=h->pos;else if(whence==SEEK_END)base=h->file->size;else{errno=EINVAL;return -1;}
    int64_t p=base+offset;if(p<0||p>SAVE_LIMIT+(int64_t)SOC_ASSET_LIMIT-SOC_ASSET_BASE){errno=EINVAL;return -1;}h->pos=(uint32_t)p;return (long)p;}
long soc_fs_size(int fd){handle_t*h=handle(fd);return h?(long)h->file->size:-1;}
