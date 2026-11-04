#include "uart_terminal.h"
#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>
static unsigned checks=0;
static void require(bool c,const char*s){if(!c)throw std::runtime_error(s);++checks;}
static void observe(UartTerminal&t,const std::string&s){for(unsigned char c:s)t.observe(c);}
static void idle(UartTerminal&t,unsigned n){while(n--)require(t.tick(),"sent another byte without fresh observed echo/prompt");}
int main(int argc,char**argv){try{
 if(argc!=3)throw std::runtime_error("usage: test script initial_blob_output");
 auto text=UartTerminal::read_bounded(argv[1]);auto terminal=UartTerminal::parse(text);
 {std::ofstream out(argv[2],std::ios::binary);terminal.save(out);}
 std::vector<UartTerminal::Stage>stages;std::istringstream lines(text);std::string line;
 while(std::getline(lines,line)){auto tab=line.find('\t');require(tab!=std::string::npos,"missing TSV separator");
 stages.push_back({UartTerminal::unescape(line.substr(0,tab)),UartTerminal::unescape(line.substr(tab+1))});}
 require(stages.size()<=128&&stages.size()>5,"stage bound");
 require(stages[0].trigger=="rv32 login:"&&stages[0].payload=="r","ordinary login missing");
 require(stages[1].trigger=="r"&&stages[1].payload=="o","first o missing");
 require(stages[2].trigger=="o"&&stages[2].payload=="o","duplicate o missing");
 require(stages[3].trigger=="o"&&stages[3].payload=="t","second echo not required");
 std::string decoded;
 for(size_t n=0;n<stages.size();n++){
  auto stage=stages[n];require(stage.payload.size()==1,"payload not single character");
  idle(terminal,30000+(n%7)*971); // no echo must mean no next start, arbitrarily long
  observe(terminal,std::string(1,char(255)));idle(terminal,37); // irrelevant observed TX
  // Preserve partial trigger tails through a save/restore before final byte.
  observe(terminal,stage.trigger.substr(0,stage.trigger.size()-1));
  {std::ostringstream s;terminal.save(s);std::istringstream in(s.str());terminal=UartTerminal::restore(in);}
  observe(terminal,stage.trigger.substr(stage.trigger.size()-1));
  unsigned char expected=stage.payload[0],received=0;
  for(unsigned bit=0;bit<10;bit++)for(unsigned tick=0;tick<868;tick++){
   bool want=bit==0?false:bit==9?true:(expected>>(bit-1))&1;
   bool pin=terminal.tick();require(pin==want,"incorrect 8N1 waveform");
   if(bit>=1&&bit<=8&&tick==434)received|=unsigned(pin)<<(bit-1);
   if(bit==3&&tick==113){std::ostringstream s;terminal.save(s);std::istringstream in(s.str());terminal=UartTerminal::restore(in);}
  }
  decoded+=char(received);require(received==expected,"decoded byte differs");
  require(terminal.sent_bytes()==n+1,"byte lost/duplicated");
  idle(terminal,8680); // mandated gap still present; no next char without echo
 }
 require(terminal.done(),"final stage incomplete");
 const std::string expected="root\nuname -a\nps\nls -l /dev/fb0\necho RV32S\ngui-command status\nsleep 1\ngui-command settings\nsleep 1\ngui-command home\necho RV32G\n";
 require(decoded==expected,"complete ordinary terminal input differs");
 std::cout<<"PASS echo pacing stages="<<stages.size()<<" pin_checks="<<checks<<" exact root/duplicate-oo/commands; fresh-echo absence holds idle; partial-trigger and midbyte restore verified\n";
 }catch(const std::exception&e){std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}}
