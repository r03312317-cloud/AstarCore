#include "Vcache.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <unordered_map>
#include <stdexcept>
#include <string>
double sc_time_stamp(){return 0;}
struct Reply{uint64_t data;unsigned error;};
struct Harness{
 Vcache d;uint32_t rng=0x398ac11;uint64_t clocks=0;unsigned ireqs=0,dreqs=0,wb=0;
 bool iact=false,dact=false,ack=false;uint32_t iba=0,dba=0,wba=0;unsigned ib=0,db=0,wbeat=0;
 std::unordered_map<uint32_t,uint32_t> mem,arch;
 std::unordered_map<uint32_t,unsigned> bad;
 std::deque<Reply> iq;std::deque<uint32_t> daq;
 bool held=false;uint64_t held_data=0;unsigned held_error=0;
 unsigned rand(){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;return rng;}
 void check(bool b,const char* msg){if(!b)throw std::runtime_error(std::string(msg)+" at cycle "+std::to_string(clocks));}
 static uint32_t word(uint32_t a){return (a*0x9e3779b9u)^(a>>11)^0x562a91c3u;}
 uint32_t load(uint32_t a){auto p=mem.find(a);return p==mem.end()?word(a):p->second;}
 uint32_t expected(uint32_t a){auto p=arch.find(a);return p==arch.end()?word(a):p->second;}
 static bool executable(uint32_t a){return (a>>28)==1||(a>>28)==8;}
 Reply instruction(uint32_t a){
  if(!executable(a)||(a&3))return {0,3};
  bool e0=bad.count(a&~63u),e1=!executable(a+4)||bad.count((a+4)&~63u);
  return {(uint64_t(e1?0:load(a+4))<<32)|(e0?0:load(a)),unsigned(e0)|(unsigned(e1)<<1)};
 }
 void reset(){
  d.imem_request_valid=0;d.imem_response_ready=1;d.dmem_request_valid=0;d.dmem_response_ready=1;
  d.fence_i=0;d.fence_d=0;d.reset=1;iact=dact=ack=held=false;ib=db=wbeat=0;iq.clear();daq.clear();
  for(int k=0;k<4;k++)tick();d.reset=0;
 }
 void tick(){
  if(clocks++>2000000)throw std::runtime_error("timeout");
  d.clk=0;d.instr_gnt_i=0;d.instr_rvalid_i=0;d.instr_err_i=0;
  d.data_rd_gnt_i=0;d.data_rd_rvalid_i=0;d.data_rd_err_i=0;d.data_rd_rid_i=0;
  d.data_wr_gnt_i=0;d.data_wr_bvalid_i=0;d.data_wr_berr_i=0;d.data_wr_bid_i=0;
  d.periph_gnt_i=0;d.periph_rvalid_i=0;d.periph_err_i=0;d.periph_rdata_i=0;d.eval();
  bool ic=!d.reset&&!iact&&d.instr_req_o&&(rand()%4!=0);
  bool dc=!d.reset&&!dact&&d.data_rd_req_o&&(rand()%4!=0);
  bool isend=!d.reset&&(iact||ic)&&(rand()%4!=0);
  bool dsend=!d.reset&&(dact||dc)&&(rand()%4!=0);
  auto ix=iact?iba:d.instr_addr_o;auto in=iact?ib:0;
  auto dx=dact?dba:d.data_rd_addr_o;auto dn=dact?db:0;
  d.instr_gnt_i=ic;d.instr_rvalid_i=isend;d.instr_rdata_i=(uint64_t(load(ix+in*8+4))<<32)|load(ix+in*8);
  d.instr_err_i=isend&&bad.count(ix)&&bad[ix]==in;
  d.data_rd_gnt_i=dc;d.data_rd_rvalid_i=dsend;d.data_rd_rdata_i=(uint64_t(load(dx+dn*8+4))<<32)|load(dx+dn*8);
  bool ws=!d.reset&&d.data_wr_req_o&&(rand()%4!=0);
  bool ba=!d.reset&&((ack&&(rand()%3!=0))||(ws&&d.data_wr_last_o&&(rand()%2==0)));
  d.data_wr_gnt_i=ws;d.data_wr_bvalid_i=ba;d.eval();
  if(!d.reset){
   if(held)check(d.imem_response_valid&&d.imem_response_data==held_data&&d.imem_response_error==held_error,"held I response changed");
   held=d.imem_response_valid&&!d.imem_response_ready;
   held_data=d.imem_response_data;held_error=d.imem_response_error;
   if(d.imem_response_valid&&d.imem_response_ready){
    check(!iq.empty(),"unexpected I response");auto r=iq.front();iq.pop_front();
    if(r.data!=d.imem_response_data||r.error!=d.imem_response_error){
     std::fprintf(stderr,"I expected %016llx/%u got %016llx/%u\n",(unsigned long long)r.data,r.error,(unsigned long long)d.imem_response_data,unsigned(d.imem_response_error));
     check(false,"I response mismatch");}
   }
   if(d.imem_request_valid&&d.imem_request_ready)iq.push_back(instruction(d.imem_request_address));
   if(ic){iact=true;iba=ix;ib=0;ireqs++;}
   if(isend&&d.instr_rready_o){if(in==7)iact=false;else ib=in+1;}
   if(dc){dact=true;dba=dx;db=0;dreqs++;}
   if(dsend&&d.data_rd_rready_o){if(dn==7)dact=false;else db=dn+1;}
   if(ws){
    if(wbeat==0)wba=d.data_wr_addr_o;
    check(wba==d.data_wr_addr_o,"writeback address changed");
    mem[wba+wbeat*8]=uint32_t(d.data_wr_data_o);mem[wba+wbeat*8+4]=uint32_t(d.data_wr_data_o>>32);
    if(d.data_wr_last_o){check(wbeat==7,"wrong burst length");wbeat=0;ack=true;wb++;}else wbeat++;
   }
   if(ba)ack=false;
  }
  d.clk=1;d.eval();
 }
 void fetch(uint32_t a,unsigned hold=0){
  d.imem_request_address=a;d.imem_request_valid=1;d.imem_response_ready=0;
  do{d.clk=0;d.eval();bool accept=d.imem_request_ready;tick();if(accept)break;}while(true);
  d.imem_request_valid=0;
  do{d.clk=0;d.eval();if(d.imem_response_valid)break;tick();}while(true);
  while(hold--)tick();d.imem_response_ready=1;tick();check(iq.empty(),"I response missing");
 }
 void stream(unsigned n){
  unsigned accepted=0;d.imem_response_ready=1;
  while(accepted<n||!iq.empty()){
   d.imem_request_valid=accepted<n;d.imem_request_address=0x10000000+((accepted*4)%256);
   d.clk=0;d.eval();bool a=d.imem_request_valid&&d.imem_request_ready;tick();if(a)accepted++;
  }d.imem_request_valid=0;
 }
 void data(uint32_t a,bool write=false,uint32_t v=0,unsigned mask=15){
  d.dmem_request_address=a;d.dmem_request_valid=1;d.dmem_request_write=write;d.dmem_request_wdata=v;d.dmem_request_wstrb=mask;d.dmem_request_size=2;d.dmem_response_ready=0;
  do{d.clk=0;d.eval();bool ok=d.dmem_request_ready;tick();if(ok)break;}while(true);d.dmem_request_valid=0;
  do{d.clk=0;d.eval();if(d.dmem_response_valid)break;tick();}while(true);
  check(!d.dmem_response_error,"D error");if(!write)check(d.dmem_response_rdata==expected(a),"D read mismatch");
  else {auto x=expected(a);for(unsigned i=0;i<4;i++)if(mask&(1u<<i))x=(x&~(255u<<(8*i)))|(v&(255u<<(8*i)));arch[a]=x;}
  d.dmem_response_ready=1;tick();
 }
 void fence(){d.fence_i=1;tick();d.fence_i=0;do{tick();d.clk=0;d.eval();}while(d.maintenance_busy);}
 void run(){
  reset();const uint32_t A=0x10000000,B=A+8192,C=A+16384;
  auto q=ireqs;fetch(A);fetch(B);check(ireqs==q+2,"I first two lines must miss");
  fetch(A,7);fetch(B,9);check(ireqs==q+2,"I two same-set tags must coexist");
  fetch(A);fetch(C);auto r=ireqs;fetch(A);check(ireqs==r,"I MRU incorrectly evicted");fetch(B);check(ireqs==r+1,"I LRU victim not evicted");
  reset();fetch(B+64);fetch(A+64);fetch(A);q=ireqs;fetch(A+60,8);check(ireqs==q,"cross-way line pair should hit");
  reset();fetch(B+64);fetch(A+64);q=ireqs;fetch(A+60,3);check(ireqs==q+1,"first-line miss must preserve next-line way");
  reset();fetch(A);fetch(B);q=ireqs;fence();fetch(A);fetch(B);check(ireqs==q+2,"FENCE.I must invalidate both ways");
  // A line formerly in way 1 refills into way 0 after invalidation. A stale
  // opposite tag must not redirect a later hit to its old RAM contents.
  reset();fetch(A);fetch(B);fence();
  mem[B]=arch[B]=0x13579bdf;mem[B+4]=arch[B+4]=0x2468ace0;
  q=ireqs;fetch(B);fetch(B,8);check(ireqs==q+1,"FENCE stale-way alias");
  reset();fetch(A);fetch(B);reset();
  mem[B]=arch[B]=0xfedcba98;mem[B+4]=arch[B+4]=0x76543210;
  q=ireqs;fetch(B);fetch(B,8);check(ireqs==q+1,"reset stale-way alias");
  stream(1500);
  q=ireqs;auto hit_start=clocks;stream(512);
  check(ireqs==q && clocks-hit_start==513,"warm I hits must sustain one request per cycle");
  for(unsigned j=0;j<5000;j++)fetch(A+(rand()%1024)*64+(rand()%16)*4,rand()%4);
  for(unsigned beat=0;beat<8;beat++){
   reset();bad.clear();bad[A]=beat;fetch(A);fetch(A+60);bad.clear();fetch(A);fetch(A+60);
   reset();bad[A+64]=beat;fetch(A+60);bad.clear();fetch(A+60);
  }
  reset();bad.clear();fetch(0x1ffffffc,4);fetch(0x20000000);fetch(A+1);
  data(A,true,0x11223344);data(A+4096,true,0xaabbccdd);q=dreqs;
  data(A);data(A+4096);check(dreqs==q,"D ways must coexist");data(A+8192,true,0x5a7eea11);data(A);
  for(unsigned j=0;j<1000;j++){uint32_t a=A+(rand()%512)*64+(rand()%16)*4;data(a,true,rand(),1u<<(rand()%4));data(a);}
  fence();for(auto x:arch)check(load(x.first)==x.second,"dirty line writeback mismatch");
  // Reset invalidates cache metadata even when an I burst is in flight.
  d.imem_request_address=A+32768;d.imem_request_valid=1;for(unsigned k=0;k<5;k++)tick();reset();fetch(A+32768);
  d.final();std::printf("PASS two_way_coexistence lru cross_way_fast_fetch miss_cross_fetch held_response back_to_back random_bursts error_all_beats executable_boundary fence_both_ways data_dirty_writeback reset_mid_burst cycles=%llu i_bursts=%u d_bursts=%u writebacks=%u\n",(unsigned long long)clocks,ireqs,dreqs,wb);
 }
};
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);Verilated::threadContextp()->threads(1);try{Harness h;h.run();return 0;}catch(const std::exception&e){std::fprintf(stderr,"FAIL %s\n",e.what());return 1;}}
