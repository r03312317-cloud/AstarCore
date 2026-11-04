#ifndef RV32_VIDEO_CHECKPOINT_H
#define RV32_VIDEO_CHECKPOINT_H
#include "verilated_save.h"
#include <array>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <fstream>
#include <filesystem>
#include <unistd.h>
#include <fcntl.h>
#include <type_traits>
// Linux host checkpoint support. sha256sum is a runtime prerequisite; all paths
// are shell-quoted and no guest-supplied text is executed as shell syntax.
inline std::string cp_quote(const std::string&s){std::string q="'";for(char c:s)q+=c=='\''?"'\\''":std::string(1,c);return q+"'";}
inline std::string cp_sha(const std::string&path,uint64_t prefix=~uint64_t(0)){
 std::string cmd=prefix==~uint64_t(0)?"sha256sum -- "+cp_quote(path):"head -c "+std::to_string(prefix)+" -- "+cp_quote(path)+" | sha256sum";
 FILE*f=popen(cmd.c_str(),"r");if(!f)throw std::runtime_error("checkpoint sha256sum unavailable");
 char buf[4096];std::string out;while(fgets(buf,sizeof(buf),f))out+=buf;
 int rc=pclose(f);if(rc||out.size()<64)throw std::runtime_error("checkpoint SHA256 failed");
 out.resize(64);if(out.find_first_not_of("0123456789abcdef")!=std::string::npos)throw std::runtime_error("invalid SHA256 output");return out;
}
inline void cp_sync(const std::string&path){int fd=open(path.c_str(),O_RDONLY);if(fd<0||fsync(fd)){if(fd>=0)close(fd);throw std::runtime_error("checkpoint fsync failed");}close(fd);}
struct CpWrite{
 VerilatedSave&s;
 template<class T>void pod(T&v){static_assert(std::is_trivially_copyable<T>::value,"POD only");s.write(&v,sizeof(v));}
 void str(std::string&v){uint64_t n=v.size();pod(n);s.write(v.data(),n);}
};
struct CpRead{
 VerilatedRestore&s;
 template<class T>void pod(T&v){static_assert(std::is_trivially_copyable<T>::value,"POD only");s.read(&v,sizeof(v));}
 void str(std::string&v){uint64_t n;pod(n);if(n>2*1024*1024)throw std::runtime_error("checkpoint string bound");v.resize(n);s.read(v.data(),n);}
};
inline void cp_verify(const std::string&path){auto n=std::filesystem::file_size(path);if(n<65||n>128ull*1024*1024)throw std::runtime_error("checkpoint size invalid");std::ifstream f(path,std::ios::binary);f.seekg(n-65);std::string expected(64,' ');f.read(expected.data(),64);if(!f||cp_sha(path,n-65)!=expected)throw std::runtime_error("checkpoint checksum mismatch");}
#endif
