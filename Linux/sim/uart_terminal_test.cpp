#include "uart_terminal.h"
#include <iostream>
#include <functional>
#include <sstream>
static unsigned checks=0;
static void require(bool b,const char*why){if(!b)throw std::runtime_error(why);++checks;}
static void observe(UartTerminal&t,const std::string&s){for(unsigned char c:s)t.observe(c);}
static void rejects(const std::function<void()>&f){bool caught=false;try{f();}catch(const std::runtime_error&){caught=true;}require(caught,"invalid configuration accepted");}
static void idle(UartTerminal&t,unsigned clocks){for(unsigned i=0;i<clocks;i++)require(t.tick(),"unexpected RX start");}
// Independent pin sampler plus per-clock exact frame comparison.
static std::string frames(UartTerminal&t,const std::string&expected,bool final_gap=true){
 std::string decoded;
 for(size_t n=0;n<expected.size();n++){
  uint8_t value=0,byte=uint8_t(expected[n]);
  for(unsigned bit=0;bit<10;bit++)for(unsigned tick=0;tick<868;tick++){
   bool pin=t.tick(),want=bit==0?false:bit==9?true:(byte>>(bit-1))&1;
   require(pin==want,"8N1 waveform or bit duration mismatch");
   if(tick==434&&bit>=1&&bit<=8)value|=uint8_t(pin)<<(bit-1);
   // A prompt observed before the last payload byte is completed must not
   // pre-arm the next script stage; simulate stale/echoed output continuously.
   if(tick==20)observe(t,"# ");
  }
  decoded+=char(value);
  if(n+1<expected.size()||final_gap)idle(t,8680);
 }
 require(decoded==expected,"UART pin decoder bytes differ");return decoded;
}
int main(int argc,char**argv){try{
 require(argc==3,"expected legacy and staged fixture files");
 unsetenv("RV32_UART_INPUT");unsetenv("RV32_UART_TRIGGER");unsetenv("RV32_UART_SCRIPT");
 auto disabled=UartTerminal::from_environment();observe(disabled,"rv32 login: # ");idle(disabled,20000);require(disabled.done(),"default not disabled");
 std::ostringstream logs;
 auto t=UartTerminal::parse("rv32 login:\troot\\n\n# \techo READY\\n\n# \t\\x00\\xff\\r\\t\\\\\n",&logs);
 observe(t,"stale # ");idle(t,1000000);require(t.sent_bytes()==0,"absent login sent bytes");
 observe(t,"rv32 logi");idle(t,300);observe(t,"n:");
 require(t.tick(true),"reset not idle"); // reset pauses without consuming a bit
 frames(t,"root\n",false);require(t.completed_stages()==1,"stage1 not completed");
 idle(t,8680+20000);require(t.sent_bytes()==5,"old prompt incorrectly reused");
 observe(t,"#");idle(t,500);observe(t," ");frames(t,"echo READY\n",false);
 require(t.completed_stages()==2,"stage2 not completed");
 // A genuinely new prompt during post-frame idle gap may arm next stage,
 // but it cannot shorten the mandatory inter-byte idle period.
 observe(t,"# ");idle(t,8680);std::string binary;binary+='\0';binary+=char(255);binary+='\r';binary+='\t';binary+='\\';frames(t,binary);
 require(t.done()&&t.sent_bytes()==21,"final stage byte count");
 observe(t,"rv32 login: # ");idle(t,20000);require(t.sent_bytes()==21,"script repeated");
 auto legacy=UartTerminal({{"# ",std::string("A\0Z",3)}});observe(legacy,"# ");frames(legacy,std::string("A\0Z",3));require(legacy.done(),"legacy incomplete");
 auto emptytrigger=UartTerminal({{"","X"}});idle(emptytrigger,100);observe(emptytrigger,"a");frames(emptytrigger,"X");
 auto crlf=UartTerminal::parse("hello\tA\\n\r\n\r\n");observe(crlf,"hello");frames(crlf,"A\n");
 rejects([]{UartTerminal::parse("missing separator");});
 rejects([]{UartTerminal::parse("a\tb\tc\n");});
 rejects([]{UartTerminal::parse("\ta\n");});rejects([]{UartTerminal::parse("a\t\n");});
 rejects([]{UartTerminal::parse("a\t\\q\n");});rejects([]{UartTerminal::parse("a\t\\x0\n");});
 rejects([]{UartTerminal::parse("a\t\\xGG\n");});rejects([]{UartTerminal::parse("a\tb\\");});
 rejects([]{UartTerminal::parse(std::string(1024*1024+1,'x'));});
 rejects([]{UartTerminal t({{std::string(4097,'x'),"a"}});});
 rejects([]{UartTerminal t({{"a",std::string(65537,'x')}});});
 rejects([]{UartTerminal t(std::vector<UartTerminal::Stage>(129,{"a","b"}));});
 rejects([]{UartTerminal::read_bounded("/nonexistent/rv32_uart_test");});
 setenv("RV32_UART_SCRIPT","x",1);setenv("RV32_UART_INPUT","y",1);
 rejects([]{UartTerminal::from_environment();});
 unsetenv("RV32_UART_SCRIPT");unsetenv("RV32_UART_INPUT");
 setenv("RV32_UART_INPUT",argv[1],1);setenv("RV32_UART_TRIGGER","custom",1);
 auto filelegacy=UartTerminal::from_environment();observe(filelegacy,"# ");idle(filelegacy,1000);observe(filelegacy,"custom");frames(filelegacy,"A\n");
 unsetenv("RV32_UART_INPUT");unsetenv("RV32_UART_TRIGGER");setenv("RV32_UART_SCRIPT",argv[2],1);
 auto filescript=UartTerminal::from_environment();observe(filescript,"login:");frames(filescript,"root\n");require(filescript.done(),"script file API incomplete");unsetenv("RV32_UART_SCRIPT");
 require(logs.str().find("stage 3 bytes transmitted")!=std::string::npos,"missing terminal log");
 std::cout<<"PASS UART terminal checks="<<checks<<" exact 868-clock 8N1, 8680-clock gaps, staged triggers, binary bytes, absence and bounds\n";
 return 0;
 }catch(const std::exception&e){std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}}
