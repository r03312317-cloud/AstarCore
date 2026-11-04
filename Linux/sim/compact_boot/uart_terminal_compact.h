#ifndef RV32_UART_TERMINAL_H
#define RV32_UART_TERMINAL_H
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <ostream>
#include <istream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

// Host external terminal only: observes decoded TX, drives actual RX pins.
// It never edits guest RAM, changes guest execution, or manufactures TX output.
class UartTerminal {
public:
 struct Stage {std::string trigger,payload;};
 static constexpr unsigned bit_ticks=234, gap_ticks=2340;
 static constexpr size_t max_file=1024*1024,max_stages=2048,max_trigger=4096,max_payload=65536;
 explicit UartTerminal(std::vector<Stage> stages={},std::ostream* log=nullptr):stages_(std::move(stages)),log_(log){
  if(stages_.size()>max_stages)throw std::runtime_error("too many UART stages");
  size_t total=0;for(const auto&s:stages_){
   if(s.payload.empty())throw std::runtime_error("empty UART stage payload");
   if(s.trigger.size()>max_trigger||s.payload.size()>max_payload)throw std::runtime_error("UART stage exceeds bound");
   total+=s.trigger.size()+s.payload.size();
  }if(total>max_file)throw std::runtime_error("UART stages exceed total bound");
 }
 static std::string read_bounded(const char*path){
  std::ifstream f(path,std::ios::binary);if(!f)throw std::runtime_error("UART input/script open failed");
  std::string s;char c;while(f.get(c)){if(s.size()==max_file)throw std::runtime_error("UART file exceeds 1 MiB");s+=c;}
  if(!f.eof())throw std::runtime_error("UART file read error");
  return s;
 }
 static std::string unescape(const std::string&s){
  std::string out;for(size_t i=0;i<s.size();i++){
   if(s[i]!='\\'){out+=s[i];continue;}
   if(++i==s.size())throw std::runtime_error("trailing UART escape");
   switch(s[i]){
   case 'n':out+='\n';break;case 'r':out+='\r';break;case 't':out+='\t';break;
   case '\\':out+='\\';break;
   case 'x':{if(i+2>=s.size())throw std::runtime_error("short UART hex escape");
    unsigned v=0;for(int j=0;j<2;j++){char c=s[++i];unsigned h;
     if(c>='0'&&c<='9')h=c-'0';else if(c>='a'&&c<='f')h=c-'a'+10;else if(c>='A'&&c<='F')h=c-'A'+10;else throw std::runtime_error("invalid UART hex escape");v=v*16+h;
    }out+=char(v);break;}
   default:throw std::runtime_error("unknown UART escape");
   }
  }return out;
 }
 static UartTerminal parse(const std::string&script,std::ostream*log=nullptr){
  if(script.size()>max_file)throw std::runtime_error("UART script exceeds bound");
  std::vector<Stage> stages;size_t start=0;
  while(start<script.size()){
   size_t end=script.find('\n',start);if(end==std::string::npos)end=script.size();
   std::string line=script.substr(start,end-start);start=end+1;
   if(!line.empty()&&line.back()=='\r')line.pop_back();
   if(line.empty())continue;
   size_t tab=line.find('\t');if(tab==std::string::npos||line.find('\t',tab+1)!=std::string::npos)throw std::runtime_error("UART script needs one literal TAB per line");
   Stage s{unescape(line.substr(0,tab)),unescape(line.substr(tab+1))};
   if(s.trigger.empty()||s.payload.empty())throw std::runtime_error("UART script trigger/payload must not be empty");
   stages.push_back(std::move(s));if(stages.size()>max_stages)throw std::runtime_error("too many UART stages");
  }return UartTerminal(std::move(stages),log);
 }
 static UartTerminal from_environment(std::ostream*log=nullptr){
  const char*script=std::getenv("RV32_UART_SCRIPT");const char*input=std::getenv("RV32_UART_INPUT");
  if(script&&input)throw std::runtime_error("set UART_SCRIPT or UART_INPUT, not both");
  if(script)return parse(read_bounded(script),log);
  if(input){auto bytes=read_bounded(input);if(bytes.empty())return UartTerminal({},log);
   const char*t=std::getenv("RV32_UART_TRIGGER");return UartTerminal({{t?t:"# ",bytes}},log);
  }return UartTerminal({},log);
 }
 void observe(uint8_t tx){
  if(active_||stage_==stages_.size())return;
  const auto&s=stages_[stage_];tail_+=char(tx);
  if(tail_.size()>s.trigger.size()&&!s.trigger.empty())tail_.erase(0,tail_.size()-s.trigger.size());
  if(s.trigger.empty()||tail_==s.trigger){
   active_=true;index_=0;phase_=0;ticks_=bit_ticks;tail_.clear();
   if(log_)*log_<<"UART_RX stage "<<stage_+1<<" trigger observed; scheduling "<<s.payload.size()<<" external terminal bytes\n";
  }
 }
 bool tick(bool reset=false){
  if(reset)return true;
  if(gap_){--gap_;return true;}
  if(!active_)return true;
  uint8_t byte=uint8_t(stages_[stage_].payload[index_]);
  bool pin=phase_==0?false:phase_==9?true:((byte>>(phase_-1))&1);
  if(--ticks_==0){ticks_=bit_ticks;if(++phase_==10){
   phase_=0;gap_=gap_ticks;++sent_;
   if(++index_==stages_[stage_].payload.size()){
    active_=false;++stage_;tail_.clear();
    if(log_)*log_<<"UART_RX stage "<<stage_<<" bytes transmitted\n";
   }
  }}return pin;
 }
 // Versioned portable binary record. May be embedded in a larger stream;
 // restore consumes exactly one record and never reloads environment/files.
 // Call between simulation clocks, after accounting for that clock's TX byte.
 void save(std::ostream&out)const{
  validate_state();
  out.write("AURT0001",8);put32(out,uint32_t(stages_.size()));
  for(const auto&s:stages_){putstr(out,s.trigger);putstr(out,s.payload);}
  put32(out,uint32_t(stage_));put32(out,uint32_t(index_));put32(out,uint32_t(sent_));
  put32(out,phase_);put32(out,ticks_);put32(out,gap_);put32(out,active_?1:0);putstr(out,tail_);
  if(!out)throw std::runtime_error("UART checkpoint write failed");
 }
 static UartTerminal restore(std::istream&in,std::ostream*log=nullptr){
  char magic[8];in.read(magic,8);
  if(!in||std::string(magic,8)!="AURT0001")throw std::runtime_error("invalid UART checkpoint version/magic");
  uint32_t count=get32(in);if(count>max_stages)throw std::runtime_error("UART checkpoint stage count exceeds bound");
  std::vector<Stage> stages;size_t total=0;
  for(uint32_t i=0;i<count;i++){
   auto trigger=getstr(in,max_trigger,max_file-total);total+=trigger.size();
   auto payload=getstr(in,max_payload,max_file-total);total+=payload.size();
   stages.push_back({std::move(trigger),std::move(payload)});
  }
  UartTerminal t(std::move(stages),log);
  t.stage_=get32(in);t.index_=get32(in);t.sent_=get32(in);
  t.phase_=get32(in);t.ticks_=get32(in);t.gap_=get32(in);
  uint32_t active=get32(in);if(active>1)throw std::runtime_error("invalid UART checkpoint active flag");
  t.active_=active!=0;t.tail_=getstr(in,max_trigger,max_trigger);
  t.validate_state();return t;
 }
 size_t completed_stages()const{return stage_;}
 size_t sent_bytes()const{return sent_;}
 bool done()const{return stage_==stages_.size()&&!active_&&!gap_;}
private:
 static void put32(std::ostream&out,uint32_t v){
  char b[4];for(unsigned i=0;i<4;i++)b[i]=char((v>>(8*i))&255);out.write(b,4);
 }
 static uint32_t get32(std::istream&in){
  unsigned char b[4];in.read(reinterpret_cast<char*>(b),4);
  if(!in)throw std::runtime_error("truncated UART checkpoint integer");
  uint32_t v=0;for(unsigned i=0;i<4;i++)v|=uint32_t(b[i])<<(8*i);return v;
 }
 static void putstr(std::ostream&out,const std::string&s){put32(out,uint32_t(s.size()));out.write(s.data(),std::streamsize(s.size()));}
 static std::string getstr(std::istream&in,size_t bound,size_t remaining){
  uint32_t n=get32(in);if(n>bound||n>remaining)throw std::runtime_error("UART checkpoint string exceeds bound");
  std::string s(n,'\0');if(n)in.read(&s[0],n);
  if(!in)throw std::runtime_error("truncated UART checkpoint string");
  return s;
 }
 void validate_state()const{
  if(stage_>stages_.size()||phase_>9||ticks_==0||ticks_>bit_ticks||gap_>gap_ticks)
   throw std::runtime_error("invalid UART checkpoint position/timing");
  size_t expected=0;for(size_t i=0;i<stage_;i++)expected+=stages_[i].payload.size();
  if(active_){
   if(stage_==stages_.size()||index_>=stages_[stage_].payload.size()||!tail_.empty())
    throw std::runtime_error("invalid active UART checkpoint");
   expected+=index_;
  }else{
   if(index_!=(stage_?stages_[stage_-1].payload.size():0)||phase_!=0||ticks_!=bit_ticks)
    throw std::runtime_error("invalid idle UART checkpoint");
   if(stage_==stages_.size()){
    if(!tail_.empty())throw std::runtime_error("completed UART checkpoint has trigger tail");
   }else if(tail_.size()>stages_[stage_].trigger.size()||
            (!tail_.empty()&&tail_==stages_[stage_].trigger))
    throw std::runtime_error("invalid UART checkpoint trigger tail");
  }
  if(sent_!=expected||(gap_&&(phase_!=0||ticks_!=bit_ticks))||
     (stages_.empty()&&gap_))throw std::runtime_error("invalid UART checkpoint accounting");
 }
 std::vector<Stage>stages_;std::ostream*log_;std::string tail_;
 size_t stage_=0,index_=0,sent_=0;unsigned phase_=0,ticks_=bit_ticks,gap_=0;bool active_=false;
};
#endif
