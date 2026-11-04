#include "uart_terminal.h"
#include <sstream>
#include <iostream>
#include <functional>
static unsigned checks=0,restores=0;
static void require(bool b,const char*s){if(!b)throw std::runtime_error(s);++checks;}
static std::string blob(const UartTerminal&t){std::ostringstream s(std::ios::binary);t.save(s);return s.str();}
static UartTerminal load(const std::string&s,std::ostream*log=nullptr){std::istringstream i(s,std::ios::binary);auto t=UartTerminal::restore(i,log);require(i.peek()==EOF,"record not fully consumed");return t;}
static void rejects(const std::function<void()>&f){bool failed=false;try{f();}catch(const std::runtime_error&){failed=true;}require(failed,"bad checkpoint accepted");}
static std::string set32(std::string s,size_t off,uint32_t v){for(unsigned j=0;j<4;j++)s.at(off+j)=char(v>>(8*j));return s;}
static void observe(UartTerminal&t,const std::string&s){for(unsigned char c:s)t.observe(c);}
int main(){try{
 std::ostringstream log1,log2;
 std::vector<UartTerminal::Stage> stages={{"login:","root\n"},{"# ",std::string("a\0\xff",3)},{"# ","x\n"}};
 UartTerminal ref(stages,&log1),resumed(stages,&log2);
 require(blob(ref).substr(0,8)=="AURT0001","magic mismatch");
 for(unsigned cycle=0;cycle<200000;cycle++){
  std::string output;
  if(cycle==10)output="log";
  if(cycle==20)output="in:";
  if(cycle==25000||cycle==100000)output="# "; // stale while current stage transmits
  if(cycle==90000)output="#";
  if(cycle==90500)output=" ";
  if(cycle==150000)output="# ";
  observe(ref,output);observe(resumed,output);
  // Repeated arbitrary mid-bit, idle-gap, active-stage and partial-trigger
  // snapshots: restores must not change a single future pin clock.
  if(cycle%137==0||cycle==10||cycle==20||cycle==90000||cycle==90500||cycle==150000){
   auto saved=blob(resumed);resumed=load(saved,&log2);++restores;
   require(blob(resumed)==saved,"noncanonical roundtrip");
  }
  bool reset=cycle<5||cycle==2000; // mid-frame reset pauses identical histories
  require(ref.tick(reset)==resumed.tick(reset),"pin diverged after resume");
  require(ref.sent_bytes()==resumed.sent_bytes(),"byte accounting diverged");
  require(ref.completed_stages()==resumed.completed_stages(),"stage accounting diverged");
  require(ref.done()==resumed.done(),"completion diverged");
 }
 require(ref.done()&&resumed.done()&&ref.sent_bytes()==10,"staged checkpoint scenario incomplete");
 require(log1.str()==log2.str(),"resume logged duplicate/missing stage events");
 require(blob(ref)==blob(resumed),"final states differ");
 auto complete=load(blob(ref));require(complete.done(),"completed record restore failed");
 UartTerminal disabled;require(load(blob(disabled)).done(),"disabled restore failed");
 UartTerminal normal({{"# ","AB"}});auto initial=blob(normal);
 // Known compact record layout also verifies fixed LE integer encoding.
 require(initial.size()==56&&uint8_t(initial[8])==1&&uint8_t(initial[12])==2,"record format changed");
 for(size_t len=0;len<initial.size();len++)rejects([&]{load(initial.substr(0,len));});
 rejects([&]{auto s=initial;s[0]='X';load(s);});
 rejects([&]{auto s=initial;s[7]='2';load(s);});
 rejects([&]{load(set32(initial,8,129));});
 rejects([&]{load(set32(initial,12,4097));});
 rejects([&]{load(set32(initial,18,65537));});
 rejects([&]{load(set32(initial,24,2));});
 rejects([&]{load(set32(initial,28,1));});
 rejects([&]{load(set32(initial,32,1));});
 rejects([&]{load(set32(initial,36,10));});
 rejects([&]{load(set32(initial,40,0));});
 rejects([&]{load(set32(initial,40,869));});
 rejects([&]{load(set32(initial,44,8681));});
 rejects([&]{load(set32(initial,48,2));});
 rejects([&]{load(set32(initial,52,4097));});
 observe(normal,"# ");for(unsigned i=0;i<1234;i++)normal.tick();auto active=blob(normal);
 rejects([&]{load(set32(active,28,2));}); // active index == payload length
 rejects([&]{load(set32(active,44,1));}); // gap in the middle of a bit
 rejects([&]{load(set32(active,48,0));}); // inactive mid-frame
 // Embedded records must leave following host state untouched.
 std::istringstream embedded(initial+"NEXT");auto embedded_terminal=UartTerminal::restore(embedded);
 require(!embedded_terminal.done()&&embedded.get()=='N',"restore consumed next host field");
 std::ostringstream broken;broken.setstate(std::ios::badbit);
 rejects([&]{normal.save(broken);});
 std::cout<<"PASS UART checkpoint checks="<<checks<<" restores="<<restores<<" exact uninterrupted/resumed pin equivalence, partial-trigger/midbyte/gap/config/error validation\n";
 }catch(const std::exception&e){std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}}
