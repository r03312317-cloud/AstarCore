#include "uart_terminal.h"
#include "Vrv32_linux_soc_top.h"
#include "verilated.h"
#include <vector>
#include <fstream>
#include <iostream>
#include <iomanip>
#include <cstdint>
#include <cstdlib>
#include <deque>
// Real RTL host RAM fixture: each I/D line response is eight ordered 64bit beats.
// The model checks all accesses and never wraps addresses into available RAM.
struct Read {bool active=false;uint32_t base=0;int beat=0,id=0;};
int main(int argc,char**argv){
 if(argc<2){std::cerr<<"usage: linux_soc_sim image.bin [max_cycles] [image.bin@hexaddr ...]\n";return 2;}
 Verilated::commandArgs(argc,argv);Vrv32_linux_soc_top d;
 constexpr uint32_t base=0x80000000,bytes=64u<<20;
 std::vector<uint8_t>mem(bytes,0);auto load=[&](const char*path,uint32_t address){std::ifstream f(path,std::ios::binary);if(!f)throw std::runtime_error("image open failed");std::vector<char>v((std::istreambuf_iterator<char>(f)),{});if(address<base||uint64_t(address)-base+v.size()>bytes)throw std::runtime_error("image outside RAM");std::copy(v.begin(),v.end(),mem.begin()+address-base);std::cout<<"LOAD "<<path<<" address=0x"<<std::hex<<address<<std::dec<<" bytes="<<v.size()<<"\n";};
 load(argv[1],base);for(int arg=3;arg<argc;arg++){std::string a=argv[arg];auto pos=a.find('@');if(pos==std::string::npos)return 2;load(a.substr(0,pos).c_str(),std::stoul(a.substr(pos+1),nullptr,16));}
 uint64_t limit=argc>2?std::strtoull(argv[2],nullptr,0):1000000,retired=0;uint32_t lastpc=0;
 std::deque<std::pair<uint32_t,uint32_t>> history; unsigned traps=0;
 uint64_t sti_count=0,mti_count=0,ecall_count=0,pagefault_count=0,last_sti=0,sti_min_gap=~uint64_t(0),sti_max_gap=0;
 struct Profile{std::string label;uint32_t pc;uint64_t count=0;};std::vector<Profile>profile;
 if(const char*arg=std::getenv("RV32_PROFILE_PC")){std::string cfg=arg;size_t begin=0;
  while(begin<cfg.size()){auto end=cfg.find(',',begin);if(end==std::string::npos)end=cfg.size();auto item=cfg.substr(begin,end-begin);auto split=item.find(':');
   if(split==std::string::npos||split==0||profile.size()==32)throw std::runtime_error("profile needs label:hexPC (max32)");
   auto pc=std::stoull(item.substr(split+1),nullptr,16);if(pc>0xffffffffull||(pc&3))throw std::runtime_error("invalid profile PC");
   profile.push_back({item.substr(0,split),uint32_t(pc),0});begin=end+1;
  }
 }
 UartTerminal terminal;
 try { terminal=UartTerminal::from_environment(&std::cerr); }
 catch(const std::exception&e){std::cerr<<"UART terminal configuration: "<<e.what()<<"\n";return 2;}
 Read i,r;int writebeat=0;uint32_t writebase=0;bool write_error=false;bool bv=false;int bid=0;bool berr=false;bool txprev=true;int txcount=0,txbit=0;uint8_t txbyte=0;
 auto rd64=[&](uint32_t a){uint64_t x=0;if(a>=base&&uint64_t(a)-base+8<=bytes)for(int b=0;b<8;b++)x|=uint64_t(mem[a-base+b])<<(8*b);return x;};
 d.reset=1;d.uart_rx=1;d.vblank=0;d.reservation_kill=0;
 for(uint64_t cycle=0;cycle<limit;cycle++){
  d.clk=0;d.reset=cycle<10;
  // Optional external terminal sends actual 8N1 RX pin waveforms after observed output.
  // Extra idle gap protects a software-driven UART without host-side handshakes.
  d.uart_rx=terminal.tick(d.reset);
  d.instr_gnt_i=!i.active;d.data_rd_gnt_i=!r.active;d.data_wr_gnt_i=!bv;
  d.instr_rvalid_i=i.active;d.instr_rdata_i=rd64(i.base+8*i.beat);d.instr_err_i=i.active&&(i.base<base||uint64_t(i.base)-base+64>bytes);
  d.data_rd_rvalid_i=r.active;d.data_rd_rdata_i=rd64(r.base+8*r.beat);d.data_rd_rid_i=r.id;d.data_rd_err_i=r.active&&(r.base<base||uint64_t(r.base)-base+64>bytes);
  d.data_wr_bvalid_i=bv;d.data_wr_bid_i=bid;d.data_wr_berr_i=berr;d.eval();
  bool ia=d.instr_req_o&&d.instr_gnt_i,ra=d.data_rd_req_o&&d.data_rd_gnt_i,wa=d.data_wr_req_o&&d.data_wr_gnt_i;
  bool ir=d.instr_rvalid_i&&d.instr_rready_o,rr=d.data_rd_rvalid_i&&d.data_rd_rready_o;
  uint32_t iad=d.instr_addr_o,rad=d.data_rd_addr_o,wad=d.data_wr_addr_o;uint64_t wd=d.data_wr_data_o;int rid=d.data_rd_id_o,wid=d.data_wr_id_o;bool last=d.data_wr_last_o;
  auto committed_retire=d.retire_valid;uint32_t committed_pc0=d.retire_pc0,committed_pc1=d.retire_pc1;
  uint32_t committed_instruction0=d.retire_instruction0,committed_instruction1=d.retire_instruction1;
  bool committed_trap=d.debug_trap&&!d.reset; // capture pre-edge decision, read committed CSRs after edge
  d.clk=1;d.eval();
  bv=false;if(ir&&++i.beat==8)i.active=false;if(rr&&++r.beat==8)r.active=false;
  if(ia){i.active=true;i.base=iad;i.beat=0;}if(ra){r.active=true;r.base=rad;r.beat=0;r.id=rid;}
  if(wa){if(writebeat==0){writebase=wad;write_error=false;}bool good=wad==writebase&&wad>=base&&uint64_t(wad)-base+64<=bytes&&!(wad&63);write_error|=!good;
   if(good)for(int b=0;b<8;b++)mem[wad-base+8*writebeat+b]=wd>>(8*b);
   if(last){bv=true;bid=wid;berr=write_error||writebeat!=7;writebeat=0;}else if(++writebeat>7){throw std::runtime_error("write burst missing last");}}
  if(committed_retire&1){retired++;lastpc=committed_pc0;history.emplace_back(committed_pc0,committed_instruction0);}if(committed_retire&2){retired++;lastpc=committed_pc1;history.emplace_back(committed_pc1,committed_instruction1);}while(history.size()>32)history.pop_front();
  for(auto&p:profile){if((committed_retire&1)&&committed_pc0==p.pc)p.count++;if((committed_retire&2)&&committed_pc1==p.pc)p.count++;}
  if(committed_trap){
   uint32_t cause=d.debug_privilege==1?d.debug_scause:d.debug_mcause;
   if(cause==0x80000005u){sti_count++;if(last_sti){auto gap=cycle-last_sti;sti_min_gap=std::min(sti_min_gap,gap);sti_max_gap=std::max(sti_max_gap,gap);}last_sti=cycle;}
   if(cause==0x80000007u)mti_count++;
   if(cause==9)ecall_count++;
   if(cause==12||cause==13||cause==15)pagefault_count++;
  }
  if(committed_trap&&traps++<30){std::cerr<<"TRAP cycle="<<cycle<<" mcause="<<std::hex<<d.debug_mcause<<" mepc="<<d.debug_mepc<<" mtval="<<d.debug_mtval<<" scause="<<d.debug_scause<<" sepc="<<d.debug_sepc<<" stval="<<d.debug_stval<<std::dec<<" recent retirement:\n";for(auto v:history)std::cerr<<std::hex<<v.first<<" "<<v.second<<"\n";std::cerr<<std::dec;}
  // UART_DIV=868, sample data at middle of each bit. No fabricated console.
  bool tx=d.uart_tx;if(!txcount&&txprev&&!tx){txcount=868+434;txbit=0;txbyte=0;}
  else if(txcount&&!--txcount){if(txbit<8){txbyte|=uint8_t(tx)<<txbit++;txcount=868;}else{std::cout<<char(txbyte)<<std::flush;terminal.observe(txbyte);}}
  txprev=tx;
  if(cycle&&cycle%1000000==0)std::cerr<<"PROGRESS cycles="<<cycle<<" retired="<<retired<<" pc=0x"<<std::hex<<lastpc<<" satp=0x"<<d.debug_satp<<" mepc=0x"<<d.debug_mepc<<" mcause=0x"<<d.debug_mcause<<" mtval=0x"<<d.debug_mtval<<" sepc=0x"<<d.debug_sepc<<" scause=0x"<<d.debug_scause<<" stval=0x"<<d.debug_stval<<std::dec<<" priv="<<int(d.debug_privilege)<<" sti="<<sti_count<<" mti="<<mti_count<<" s_ecall="<<ecall_count<<" pagefaults="<<pagefault_count<<" sti_gap_min="<<(sti_count>1?sti_min_gap:0)<<" sti_gap_max="<<sti_max_gap<<"\n";
  if(cycle&&cycle%1000000==0&&!profile.empty()){std::cerr<<"PROFILE cycles="<<cycle;for(auto&p:profile)std::cerr<<" "<<p.label<<"="<<p.count;std::cerr<<"\n";}
  if(Verilated::gotFinish())break;
 }
 std::cerr<<"STOP max_cycles="<<limit<<" retired="<<retired<<" last_pc=0x"<<std::hex<<lastpc<<" satp=0x"<<d.debug_satp<<" mepc=0x"<<d.debug_mepc<<" mcause=0x"<<d.debug_mcause<<" mtval=0x"<<d.debug_mtval<<" sepc=0x"<<d.debug_sepc<<" scause=0x"<<d.debug_scause<<" stval=0x"<<d.debug_stval<<std::dec<<" priv="<<int(d.debug_privilege)<<" (not a Linux success assertion)\n";
 d.final();return 0;
}
