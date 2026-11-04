#include "Vrv32_linux_video_top.h"
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
 if(argc<2){std::cerr<<"usage: linux_soc_sim image.bin [max_cycles] [dtb.bin@hexaddr]\n";return 2;}
 Verilated::commandArgs(argc,argv);Vrv32_linux_video_top d;
 constexpr uint32_t base=0x80000000,bytes=64u<<20;
 std::vector<uint8_t>mem(bytes,0);auto load=[&](const char*path,uint32_t address){std::ifstream f(path,std::ios::binary);if(!f)throw std::runtime_error("image open failed");std::vector<char>v((std::istreambuf_iterator<char>(f)),{});if(address<base||uint64_t(address)-base+v.size()>bytes)throw std::runtime_error("image outside RAM");std::copy(v.begin(),v.end(),mem.begin()+address-base);std::cout<<"LOAD "<<path<<" address=0x"<<std::hex<<address<<std::dec<<" bytes="<<v.size()<<"\n";};
 load(argv[1],base);for(int arg=3;arg<argc;arg++){std::string a=argv[arg];auto pos=a.find('@');if(pos==std::string::npos)return 2;load(a.substr(0,pos).c_str(),std::stoul(a.substr(pos+1),nullptr,16));}
 uint64_t limit=argc>2?std::strtoull(argv[2],nullptr,0):1000000,retired=0;uint32_t lastpc=0;
 std::deque<std::pair<uint32_t,uint32_t>> history; unsigned traps=0;
 bool dpending=false;uint32_t da=0;uint64_t display_reads=0,pixel_checks=0;unsigned complete_frames=0;bool checking=false;uint32_t checked_base=0,frame_hash=0x811c9dc5;
 auto expectedPixel=[](uint32_t page,unsigned x,unsigned y)->uint16_t{if(page==0x83f00000){if(y==0&&x==0)return 0xf800;if(y==0&&x==1)return 0x07e0;if(y==100&&(x==100||x==101))return 0x001f;}else if(page==0x83f70800){if(y==0&&x==0)return 0xffff;if(y==0&&x==1)return 0xffe0;}else throw std::runtime_error("unexpected scan page");return 0;};
 Read i,r;int writebeat=0;uint32_t writebase=0;bool write_error=false;bool bv=false;int bid=0;bool berr=false;bool txprev=true;int txcount=0,txbit=0;uint8_t txbyte=0;
 auto rd64=[&](uint32_t a){uint64_t x=0;if(a>=base&&uint64_t(a)-base+8<=bytes)for(int b=0;b<8;b++)x|=uint64_t(mem[a-base+b])<<(8*b);return x;};
 d.reset=1;d.uart_rx=1;d.reservation_kill=0;
 for(uint64_t cycle=0;cycle<limit;cycle++){
  d.clk=0;d.reset=cycle<10;
  d.instr_gnt_i=!i.active;d.data_rd_gnt_i=!r.active;d.data_wr_gnt_i=!bv;
  d.instr_rvalid_i=i.active;d.instr_rdata_i=rd64(i.base+8*i.beat);d.instr_err_i=i.active&&(i.base<base||uint64_t(i.base)-base+64>bytes);
  d.data_rd_rvalid_i=r.active;d.data_rd_rdata_i=rd64(r.base+8*r.beat);d.data_rd_rid_i=r.id;d.data_rd_err_i=r.active&&(r.base<base||uint64_t(r.base)-base+64>bytes);
  d.display_req_ready=!dpending&&(cycle%5!=0);d.display_rsp_valid=dpending;
  d.display_rsp_data=uint32_t(rd64(da));d.display_rsp_error=dpending&&(da<0x83f00000||da>=0x84000000);
  d.data_wr_bvalid_i=bv;d.data_wr_bid_i=bid;d.data_wr_berr_i=berr;d.eval();
  bool ia=d.instr_req_o&&d.instr_gnt_i,ra=d.data_rd_req_o&&d.data_rd_gnt_i,wa=d.data_wr_req_o&&d.data_wr_gnt_i;
  bool ir=d.instr_rvalid_i&&d.instr_rready_o,rr=d.data_rd_rvalid_i&&d.data_rd_rready_o;
  uint32_t iad=d.instr_addr_o,rad=d.data_rd_addr_o,wad=d.data_wr_addr_o;uint64_t wd=d.data_wr_data_o;int rid=d.data_rd_id_o,wid=d.data_wr_id_o;bool last=d.data_wr_last_o;
  bool dq=d.display_req_valid&&d.display_req_ready,dr=d.display_rsp_valid&&d.display_rsp_ready;uint32_t dqa=d.display_req_addr;
  d.clk=1;d.eval();
  if(dr)dpending=false;if(dq){dpending=true;da=dqa;display_reads++;}
  if(d.video_de&&d.video_x==0&&d.video_y==0&&d.framebuffer_enable){checking=true;checked_base=d.framebuffer_base;frame_hash=0x811c9dc5;}
  if(checking&&d.video_de){uint16_t expected=expectedPixel(checked_base,d.video_x/2,d.video_y/2);pixel_checks++;
   if(d.video_rgb565!=expected){std::cerr<<"VIDEO MISMATCH xy="<<d.video_x<<","<<d.video_y<<" actual="<<std::hex<<d.video_rgb565<<" expected="<<expected<<std::dec<<"\n";return 3;}
   frame_hash=(frame_hash^d.video_rgb565)*0x01000193u;
   if(d.video_x==1279&&d.video_y==719){complete_frames++;checking=false;std::cout<<"VIDEO FRAME PASS base="<<std::hex<<checked_base<<" hash="<<frame_hash<<std::dec<<"\n";
    if(complete_frames==2){if(d.video_underflow_rows||d.video_dma_errors||d.video_bounds_errors)throw std::runtime_error("unexpected scan errors");std::cout<<"PASS CPU video ownership pixels="<<pixel_checks<<" display_reads="<<display_reads<<" retired="<<retired<<"\n";return 0;}}
  }
  bv=false;if(ir&&++i.beat==8)i.active=false;if(rr&&++r.beat==8)r.active=false;
  if(ia){i.active=true;i.base=iad;i.beat=0;}if(ra){r.active=true;r.base=rad;r.beat=0;r.id=rid;}
  if(wa){if(writebeat==0){writebase=wad;write_error=false;}bool good=wad==writebase&&wad>=base&&uint64_t(wad)-base+64<=bytes&&!(wad&63);write_error|=!good;
   if(good)for(int b=0;b<8;b++)mem[wad-base+8*writebeat+b]=wd>>(8*b);
   if(last){bv=true;bid=wid;berr=write_error||writebeat!=7;writebeat=0;}else if(++writebeat>7){throw std::runtime_error("write burst missing last");}}
  if(d.retire_valid&1){retired++;lastpc=d.retire_pc0;history.emplace_back(d.retire_pc0,d.retire_instruction0);}if(d.retire_valid&2){retired++;lastpc=d.retire_pc1;history.emplace_back(d.retire_pc1,d.retire_instruction1);}while(history.size()>32)history.pop_front();
  if(d.debug_trap&&traps++<30){std::cerr<<"TRAP cycle="<<cycle<<" mcause="<<std::hex<<d.debug_mcause<<" mepc="<<d.debug_mepc<<" mtval="<<d.debug_mtval<<" scause="<<d.debug_scause<<" sepc="<<d.debug_sepc<<" stval="<<d.debug_stval<<std::dec<<" recent retirement:\n";for(auto v:history)std::cerr<<std::hex<<v.first<<" "<<v.second<<"\n";std::cerr<<std::dec;}
  // UART_DIV=868, sample data at middle of each bit. No fabricated console.
  bool tx=d.uart_tx;if(!txcount&&txprev&&!tx){txcount=868+434;txbit=0;txbyte=0;}
  else if(txcount&&!--txcount){if(txbit<8){txbyte|=uint8_t(tx)<<txbit++;txcount=868;}else{std::cout<<char(txbyte)<<std::flush;}}
  txprev=tx;
  if(cycle&&cycle%1000000==0)std::cerr<<"PROGRESS cycles="<<cycle<<" retired="<<retired<<" pc=0x"<<std::hex<<lastpc<<" satp=0x"<<d.debug_satp<<std::dec<<" priv="<<int(d.debug_privilege)<<"\n";
  if(Verilated::gotFinish())break;
 }
 std::cerr<<"STOP max_cycles="<<limit<<" retired="<<retired<<" last_pc=0x"<<std::hex<<lastpc<<" satp=0x"<<d.debug_satp<<std::dec<<" priv="<<int(d.debug_privilege)<<" (not a Linux success assertion)\n";
 d.final();return 4;
}
