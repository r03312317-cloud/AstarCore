#include "uart_terminal_compact.h"
#ifdef RV32_SAVABLE
#include "../video_checkpoint.h"
#endif
#include "Vrv32_linux_compact_sim_top.h"
#include "verilated.h"
#include <vector>
#include <fstream>
#include <iostream>
#include <iomanip>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <filesystem>
#include <sstream>
#include <algorithm>
// Real RTL host RAM fixture: each I/D line response is eight ordered 64bit beats.
// The model checks all accesses and never wraps addresses into available RAM.
struct Read {bool active=false;uint32_t base=0;int beat=0,id=0;};
int main(int argc,char**argv){
 if(argc<2){std::cerr<<"usage: linux_video_boot_sim image.bin [max_cycles] [image.bin@hexaddr ...]\n";return 2;}
 Verilated::commandArgs(argc,argv);Vrv32_linux_compact_sim_top d;
 constexpr uint32_t base=0x80000000,bytes=64u<<20;
 std::string input_identity;
 std::vector<uint8_t>mem(bytes,0);auto load=[&](const char*path,uint32_t address){std::ifstream f(path,std::ios::binary);if(!f)throw std::runtime_error("image open failed");std::vector<char>v((std::istreambuf_iterator<char>(f)),{});if(address<base||uint64_t(address)-base+v.size()>bytes)throw std::runtime_error("image outside RAM");std::copy(v.begin(),v.end(),mem.begin()+address-base);
#ifdef RV32_SAVABLE
 input_identity+=std::to_string(address)+":"+std::to_string(v.size())+":"+cp_sha(path)+";";
#endif
std::cout<<"LOAD "<<path<<" address=0x"<<std::hex<<address<<std::dec<<" bytes="<<v.size()<<"\n";};
 load(argv[1],base);for(int arg=3;arg<argc;arg++){std::string a=argv[arg];auto pos=a.find('@');if(pos==std::string::npos)return 2;auto address=std::stoull(a.substr(pos+1),nullptr,16);if(address>0xffffffffull)throw std::runtime_error("image address exceeds RV32 physical fixture");load(a.substr(0,pos).c_str(),uint32_t(address));}
 uint64_t limit=argc>2?std::strtoull(argv[2],nullptr,0):1000000,retired=0;uint32_t lastpc=0;
 std::deque<std::pair<uint32_t,uint32_t>> history; unsigned traps=0;std::string terminal_tail;uint64_t done_cycle=0;
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
 // Frame capture observes actual RTL output; it never manufactures GUI success.
 std::string capture_dir; if(const char*p=std::getenv("RV32_VIDEO_OUTPUT"))capture_dir=p;
 unsigned max_captures=8,stop_frames=0;
 if(const char*p=std::getenv("RV32_VIDEO_MAX_CAPTURES"))max_captures=std::min(64ul,std::strtoul(p,nullptr,0));
 if(const char*p=std::getenv("RV32_VIDEO_STOP_AFTER_FRAMES"))stop_frames=std::strtoul(p,nullptr,0);
 if(!capture_dir.empty())std::filesystem::create_directories(capture_dir);
 bool dpending=false,checking=false,have_hash=false,display_stalled=false;uint32_t da=0,display_held=0;
 uint64_t display_reads=0,total_pixels=0;unsigned complete_frames=0,captures=0,frame_pixels=0;
 uint32_t checked_base=0,frame_hash=0x811c9dc5,last_hash=0;
 uint32_t frame_underflow=0,frame_dma_error=0,frame_bounds_error=0;
 std::vector<uint16_t>scan_pixels(720*480);
 auto capture=[&](uint64_t cycle){
   if(capture_dir.empty()||captures>=max_captures)return;
   std::ostringstream stem;stem<<capture_dir<<"/scan_"<<std::setw(6)<<std::setfill('0')<<complete_frames<<"_"<<std::hex<<std::setw(8)<<frame_hash;
   if(std::filesystem::exists(stem.str()+".rgb565")||std::filesystem::exists(stem.str()+".ppm")||std::filesystem::exists(stem.str()+".json"))throw std::runtime_error("capture would overwrite previous evidence; choose a new output directory");
   std::ofstream raw(stem.str()+".rgb565",std::ios::binary),ppm(stem.str()+".ppm",std::ios::binary),meta(stem.str()+".json");
   if(!raw||!ppm||!meta)throw std::runtime_error("frame capture output open failed");
   ppm<<"P6\n1280 480\n255\n";
   for(uint16_t p:scan_pixels){raw.put(char(p));raw.put(char(p>>8));unsigned r=(p>>11)&31,g=(p>>5)&63,b=p&31;ppm.put(char((r<<3)|(r>>2)));ppm.put(char((g<<2)|(g>>4)));ppm.put(char((b<<3)|(b>>2)));}
   meta<<"{\n  \"source\": \"actual RTL digital scanout\",\n  \"width\": 720, \"height\": 480, \"format\": \"RGB565 little-endian\",\n  \"frame_number\": "<<complete_frames<<", \"cycle\": "<<cycle<<",\n  \"base\": \"0x"<<std::hex<<checked_base<<"\", \"fnv1a_pixel16\": \""<<frame_hash<<"\",\n"<<std::dec
       <<"  \"underflow_rows_delta\": "<<d.video_underflow_rows-frame_underflow<<", \"dma_errors_delta\": "<<d.video_dma_errors-frame_dma_error<<", \"bounds_errors_delta\": "<<d.video_bounds_errors-frame_bounds_error<<",\n  \"linux_gui_validated\": false, \"physical_hdmi_validated\": false\n}\n";
   if(!raw||!ppm||!meta)throw std::runtime_error("frame capture write failed");captures++;
 };
 Read i,r;int writebeat=0;uint32_t writebase=0;bool write_error=false;bool bv=false;int bid=0;bool berr=false;bool txprev=true;int txcount=0,txbit=0;uint8_t txbyte=0;
 auto rd64=[&](uint32_t a){uint64_t x=0;if(a>=base&&uint64_t(a)-base+8<=bytes)for(int b=0;b<8;b++)x|=uint64_t(mem[a-base+b])<<(8*b);return x;};
 d.reset=1;d.uart_rx=1;d.reservation_kill=0;
 uint64_t next_cycle=0;
#ifdef RV32_SAVABLE
 std::string checkpoint_path,resume_path;
 if(const char*p=std::getenv("RV32_CHECKPOINT"))checkpoint_path=p;
 if(const char*p=std::getenv("RV32_RESUME"))resume_path=p;
 uint64_t checkpoint_interval=10000000;
 if(const char*p=std::getenv("RV32_CHECKPOINT_INTERVAL")){checkpoint_interval=std::stoull(p);if(!checkpoint_interval)throw std::runtime_error("checkpoint interval must be nonzero");}
 bool stop_checkpoint=std::getenv("RV32_STOP_AFTER_CHECKPOINT")!=nullptr;
 std::string model_identity=cp_sha("/proc/"+std::to_string(getpid())+"/exe");
 std::ostringstream initial_terminal_stream;terminal.save(initial_terminal_stream);
 std::string config_identity=initial_terminal_stream.str();
 for(const auto&p:profile)config_identity+="\n"+p.label+":"+std::to_string(p.pc);
 // One versioned file covers RTL and every host value needed at a completed
 // cycle boundary. Never save between evaluation and its host-side effects.
 auto host_state=[&](auto&a){
  a.pod(next_cycle);a.pod(retired);a.pod(lastpc);a.pod(traps);a.str(terminal_tail);a.pod(done_cycle);
  a.pod(sti_count);a.pod(mti_count);a.pod(ecall_count);a.pod(pagefault_count);a.pod(last_sti);a.pod(sti_min_gap);a.pod(sti_max_gap);
  a.pod(i.active);a.pod(i.base);a.pod(i.beat);a.pod(i.id);a.pod(r.active);a.pod(r.base);a.pod(r.beat);a.pod(r.id);
  a.pod(writebeat);a.pod(writebase);a.pod(write_error);a.pod(bv);a.pod(bid);a.pod(berr);
  a.pod(txprev);a.pod(txcount);a.pod(txbit);a.pod(txbyte);
  a.pod(dpending);a.pod(checking);a.pod(have_hash);a.pod(display_stalled);a.pod(da);a.pod(display_held);
  a.pod(display_reads);a.pod(total_pixels);a.pod(complete_frames);a.pod(captures);a.pod(frame_pixels);
  a.pod(checked_base);a.pod(frame_hash);a.pod(last_hash);a.pod(frame_underflow);a.pod(frame_dma_error);a.pod(frame_bounds_error);
  for(auto&p:profile)a.pod(p.count);
 };
 auto save_checkpoint=[&](){
  std::string tmp=checkpoint_path+".tmp."+std::to_string(getpid());
  VerilatedSave out;out.open(tmp);if(!out.isOpen())throw std::runtime_error("checkpoint open failed");CpWrite a{out};
  std::string magic="RV32_VIDEO_CHECKPOINT_V1";a.str(magic);a.str(model_identity);a.str(input_identity);a.str(config_identity);
  host_state(a);uint64_t hn=history.size();a.pod(hn);for(auto&p:history){a.pod(p.first);a.pod(p.second);}
  std::ostringstream ts;terminal.save(ts);std::string tb=ts.str();a.str(tb);
  out.write(mem.data(),mem.size());out.write(scan_pixels.data(),scan_pixels.size()*sizeof(uint16_t));out<<d;out.close();
  std::string digest=cp_sha(tmp);{std::ofstream f(tmp,std::ios::binary|std::ios::app);f<<digest<<"\n";if(!f)throw std::runtime_error("checkpoint checksum append failed");}
  cp_sync(tmp);std::filesystem::rename(tmp,checkpoint_path);
  auto parent=std::filesystem::path(checkpoint_path).parent_path();cp_sync(parent.empty()?".":parent.string());
  std::cerr<<"CHECKPOINT next_cycle="<<next_cycle<<" path="<<checkpoint_path<<" sha256_payload="<<digest<<"\n";
 };
 if(!resume_path.empty()){
  cp_verify(resume_path);VerilatedRestore in;in.open(resume_path);if(!in.isOpen())throw std::runtime_error("checkpoint restore open failed");CpRead a{in};
  std::string magic,model,inputs,config;a.str(magic);a.str(model);a.str(inputs);a.str(config);
  if(magic!="RV32_VIDEO_CHECKPOINT_V1"||model!=model_identity||inputs!=input_identity||config!=config_identity)throw std::runtime_error("checkpoint model/input/terminal/profile identity mismatch");
  host_state(a);uint64_t hn;a.pod(hn);if(hn>32)throw std::runtime_error("checkpoint history bound");history.clear();
  while(hn--){uint32_t pc,ins;a.pod(pc);a.pod(ins);history.emplace_back(pc,ins);}
  std::string tb;a.str(tb);std::istringstream ts(tb);terminal=UartTerminal::restore(ts,&std::cerr);if(ts.peek()!=std::char_traits<char>::eof())throw std::runtime_error("checkpoint terminal trailing bytes");
  in.read(mem.data(),mem.size());in.read(scan_pixels.data(),scan_pixels.size()*sizeof(uint16_t));in>>d;in.close();
  if(next_cycle<10||next_cycle>limit)throw std::runtime_error("checkpoint cycle beyond requested limit");
  std::cerr<<"RESUME next_cycle="<<next_cycle<<" path="<<resume_path<<"\n";
 }
#else
 if(std::getenv("RV32_CHECKPOINT")||std::getenv("RV32_RESUME"))throw std::runtime_error("rebuild with RV32_SAVABLE=1 for checkpoints");
#endif
 for(uint64_t cycle=next_cycle;cycle<limit;cycle++){
  d.clk=0;d.reset=cycle<10;
  // Optional external terminal sends actual 8N1 RX pin waveforms after observed output.
  // Extra idle gap protects a software-driven UART without host-side handshakes.
  d.uart_rx=terminal.tick(d.reset);
  d.instr_gnt_i=!i.active;d.data_rd_gnt_i=!r.active;d.data_wr_gnt_i=!bv;
  d.instr_rvalid_i=i.active;d.instr_rdata_i=rd64(i.base+8*i.beat);d.instr_err_i=i.active&&(i.base<base||uint64_t(i.base)-base+64>bytes);
  d.data_rd_rvalid_i=r.active;d.data_rd_rdata_i=rd64(r.base+8*r.beat);d.data_rd_rid_i=r.id;d.data_rd_err_i=r.active&&(r.base<base||uint64_t(r.base)-base+64>bytes);
  d.display_req_ready=!dpending&&(cycle%5!=0);d.display_rsp_valid=dpending;
  uint64_t dl=rd64(da),dh=rd64(da+8);d.display_rsp_data[0]=uint32_t(dl);d.display_rsp_data[1]=uint32_t(dl>>32);d.display_rsp_data[2]=uint32_t(dh);d.display_rsp_data[3]=uint32_t(dh>>32);d.display_rsp_error=dpending&&(da<0x83f00000||uint64_t(da)+16>0x84000000ull||(da&15));
  d.data_wr_bvalid_i=bv;d.data_wr_bid_i=bid;d.data_wr_berr_i=berr;d.eval();
  bool ia=d.instr_req_o&&d.instr_gnt_i,ra=d.data_rd_req_o&&d.data_rd_gnt_i,wa=d.data_wr_req_o&&d.data_wr_gnt_i;
  bool ir=d.instr_rvalid_i&&d.instr_rready_o,rr=d.data_rd_rvalid_i&&d.data_rd_rready_o;
  uint32_t iad=d.instr_addr_o,rad=d.data_rd_addr_o,wad=d.data_wr_addr_o;uint64_t wd=d.data_wr_data_o;int rid=d.data_rd_id_o,wid=d.data_wr_id_o;bool last=d.data_wr_last_o;
  if(display_stalled&&(!d.display_req_valid||d.display_req_addr!=display_held))throw std::runtime_error("display request changed under backpressure");
  display_stalled=d.display_req_valid&&!d.display_req_ready;display_held=d.display_req_addr;
  bool dq=d.display_req_valid&&d.display_req_ready,dr=d.display_rsp_valid&&d.display_rsp_ready;uint32_t dqa=d.display_req_addr;
  if(dq&&(dqa<0x83f00000||uint64_t(dqa)+16>0x84000000ull||(dqa&15)))throw std::runtime_error("display read outside reserved aligned region");
  auto committed_retire=d.retire_valid;uint32_t committed_pc0=d.retire_pc0,committed_pc1=d.retire_pc1;
  uint32_t committed_instruction0=d.retire_instruction0,committed_instruction1=d.retire_instruction1;
  bool committed_trap=d.debug_trap&&!d.reset; // capture pre-edge decision, read committed CSRs after edge
  d.clk=1;d.eval();
  if(dr)dpending=false;if(dq){dpending=true;da=dqa;display_reads++;}
  if(d.video_de&&d.video_x==0&&d.video_y==0&&d.framebuffer_enable){
   checking=true;checked_base=d.framebuffer_base;frame_hash=0x811c9dc5;frame_pixels=0;
   frame_underflow=d.video_underflow_rows;frame_dma_error=d.video_dma_errors;frame_bounds_error=d.video_bounds_errors;
  }
  if(checking&&d.video_de){
   if(d.video_x>=720||d.video_y>=480||unsigned(d.video_y)*720+d.video_x!=frame_pixels)throw std::runtime_error("raster coordinate/order violation");
   scan_pixels[frame_pixels++]=d.video_rgb565;total_pixels++;frame_hash=(frame_hash^d.video_rgb565)*0x01000193u;
   if(frame_pixels==720*480){complete_frames++;checking=false;
    if(!have_hash||frame_hash!=last_hash){std::cerr<<"VIDEO_FRAME observed frame="<<complete_frames<<" cycle="<<cycle<<" base=0x"<<std::hex<<checked_base<<" hash="<<frame_hash<<std::dec
     <<" underflow="<<d.video_underflow_rows<<" dma_errors="<<d.video_dma_errors<<" bounds_errors="<<d.video_bounds_errors<<" (not a GUI success assertion)\n";capture(cycle);last_hash=frame_hash;have_hash=true;}
    if(stop_frames&&complete_frames>=stop_frames){std::cerr<<"VIDEO_STOP observed_frames="<<complete_frames<<" pixels="<<total_pixels<<" reads="<<display_reads<<" captures="<<captures<<"\n";d.final();return 0;}
   }
  }
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
  bool tx=d.uart_tx;if(!txcount&&txprev&&!tx){txcount=234+117;txbit=0;txbyte=0;}
  else if(txcount&&!--txcount){if(txbit<8){txbyte|=uint8_t(tx)<<txbit++;txcount=234;}else{std::cout<<char(txbyte)<<std::flush;terminal.observe(txbyte);terminal_tail+=char(txbyte);if(terminal_tail.size()>256)terminal_tail.erase(0,terminal_tail.size()-256);if(!done_cycle&&(terminal_tail.find("\nCORE01_LINUX_TEST_DONE\r\n")!=std::string::npos||terminal_tail.find("\nCORE01_LINUX_TEST_DONE\n")!=std::string::npos))done_cycle=cycle;}}
  txprev=tx;
  if(cycle&&cycle%1000000==0)std::cerr<<"PROGRESS cycles="<<cycle<<" retired="<<retired<<" pc=0x"<<std::hex<<lastpc<<" satp=0x"<<d.debug_satp<<" mepc=0x"<<d.debug_mepc<<" mcause=0x"<<d.debug_mcause<<" mtval=0x"<<d.debug_mtval<<" sepc=0x"<<d.debug_sepc<<" scause=0x"<<d.debug_scause<<" stval=0x"<<d.debug_stval<<std::dec<<" priv="<<int(d.debug_privilege)<<" sti="<<sti_count<<" mti="<<mti_count<<" s_ecall="<<ecall_count<<" pagefaults="<<pagefault_count<<" sti_gap_min="<<(sti_count>1?sti_min_gap:0)<<" sti_gap_max="<<sti_max_gap<<"\n";
  if(cycle&&cycle%1000000==0&&!profile.empty()){std::cerr<<"PROFILE cycles="<<cycle;for(auto&p:profile)std::cerr<<" "<<p.label<<"="<<p.count;std::cerr<<"\n";}
  next_cycle=cycle+1;
#ifdef RV32_SAVABLE
  if(!checkpoint_path.empty()&&next_cycle>=10&&next_cycle%checkpoint_interval==0){save_checkpoint();if(stop_checkpoint){d.final();return 0;}}
#endif
  if(done_cycle&&cycle>done_cycle+1000000){std::cerr<<"LINUX_SCRIPT_COMPLETE cycles="<<cycle<<" frames="<<complete_frames<<" reads="<<display_reads<<" underflow="<<d.video_underflow_rows<<" dma_errors="<<d.video_dma_errors<<" bounds_errors="<<d.video_bounds_errors<<"\n";d.final();return 0;}
  if(Verilated::gotFinish())break;
 }
 std::cerr<<"STOP max_cycles="<<limit<<" retired="<<retired<<" last_pc=0x"<<std::hex<<lastpc<<" satp=0x"<<d.debug_satp<<" mepc=0x"<<d.debug_mepc<<" mcause=0x"<<d.debug_mcause<<" mtval=0x"<<d.debug_mtval<<" sepc=0x"<<d.debug_sepc<<" scause=0x"<<d.debug_scause<<" stval=0x"<<d.debug_stval<<std::dec<<" priv="<<int(d.debug_privilege)<<" (not a Linux success assertion)\n";
 std::cerr<<"VIDEO_SUMMARY frames="<<complete_frames<<" pixels="<<total_pixels<<" reads="<<display_reads<<" captures="<<captures<<" underflow="<<d.video_underflow_rows<<" dma_errors="<<d.video_dma_errors<<" bounds_errors="<<d.video_bounds_errors<<"\n";
 d.final();return 0;
}
