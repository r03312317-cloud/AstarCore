// CPU-local page 0x70000200 is GRAPH_EXECUTOR1. Existing NPU pages and the board MMIO
// window retain ordered request/response semantics. Graph and CPU requests
// arbitrate per transaction, so a device job does not hold the CPU bus.
// 架构导读：soc_graph_mmio_fabric。
// 在 CPU 与图执行器之间维护加速器 MMIO 的请求和响应所有权。
module soc_graph_mmio_fabric #(parameter integer PROGRAM_ADDR_BITS=13)(
 // 接口声明：input logic clk,rst。
 // 参与复位或清空条件；极性和同步边界以使用它的过程为准。
 input logic clk,rst,
 // 接口声明：input logic cn_req_valid,output logic cn_req_ready,input logic [15:0] cn_req_addr。
 // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
 input logic cn_req_valid,output logic cn_req_ready,input logic [15:0] cn_req_addr,
 // 接口声明：input logic cn_req_write,input logic [31:0] cn_req_wdata,input logic [3:0] cn_req_wstrb。
 // 按字节选择本次写入生效的 lane。
 input logic cn_req_write,input logic [31:0] cn_req_wdata,input logic [3:0] cn_req_wstrb,
 // 接口声明：output logic cn_rsp_valid,input logic cn_rsp_ready,output logic [31:0] cn_rsp_rdata,output logic cn_rsp_error。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 output logic cn_rsp_valid,input logic cn_rsp_ready,output logic [31:0] cn_rsp_rdata,output logic cn_rsp_error,
 // 接口声明：output logic n_req_valid,input logic n_req_ready,output logic [15:0] n_req_addr。
 // 用于地址/基址选择，访问步长和对齐还受相应描述符约束。
 output logic n_req_valid,input logic n_req_ready,output logic [15:0] n_req_addr,
 // 接口声明：output logic n_req_write,output logic [31:0] n_req_wdata,output logic [3:0] n_req_wstrb。
 // 按字节选择本次写入生效的 lane。
 output logic n_req_write,output logic [31:0] n_req_wdata,output logic [3:0] n_req_wstrb,
 // 接口声明：input logic n_rsp_valid,output logic n_rsp_ready,input logic [31:0] n_rsp_rdata,input logic n_rsp_error。
 // 记录异常状态；查看置位与清除分支可确定其保持范围。
 input logic n_rsp_valid,output logic n_rsp_ready,input logic [31:0] n_rsp_rdata,input logic n_rsp_error,
 // 接口声明：input logic cb_req_valid,output logic cb_req_ready,input logic [31:0] cb_req_addr,cb_req_wdata。
 // 保存/传递数据负载，数据有效性由独立控制字段约束。
 input logic cb_req_valid,output logic cb_req_ready,input logic [31:0] cb_req_addr,cb_req_wdata,
 // 接口声明：input logic cb_req_write,cb_req_fetch,input logic [3:0] cb_req_wstrb。
 // 按字节选择本次写入生效的 lane。
 input logic cb_req_write,cb_req_fetch,input logic [3:0] cb_req_wstrb,
 output logic cb_rsp_valid,input logic cb_rsp_ready,output logic [31:0] cb_rsp_rdata,output logic cb_rsp_error,
 output logic b_req_valid,input logic b_req_ready,output logic [31:0] b_req_addr,b_req_wdata,
 output logic b_req_write,b_req_fetch,output logic [3:0] b_req_wstrb,
 input logic b_rsp_valid,output logic b_rsp_ready,input logic [31:0] b_rsp_rdata,input logic b_rsp_error,
 output logic graph_busy,graph_poison,graph_input_consumed
);
 logic local_owner,cn_busy;
 wire local_select=cn_req_addr[15:8]==8'h02;
 logic l_req_ready,l_rsp_valid,l_rsp_ready,l_rsp_error;
 logic [31:0] l_rsp_data;
 logic g_req_valid,g_req_ready,g_req_write,g_rsp_valid,g_rsp_ready,g_rsp_error;
 logic [31:0] g_req_addr,g_req_data,g_rsp_data;logic [3:0] g_req_strb;
 logic [1:0] nv,nr,nsv,nsr,nse,bv,br,bsv,bsr,bse;
 logic [1:0][31:0] na,nd,nsd,ba,bd,bsd;
 logic [31:0] unused_n_full_addr;logic n_unused_fetch;
 assign cn_req_ready=!cn_busy&&(local_select?l_req_ready:nr[0]);
 assign cn_rsp_valid=cn_busy&&(local_owner?l_rsp_valid:nsv[0]);
 assign cn_rsp_rdata=local_owner?l_rsp_data:nsd[0];
 assign cn_rsp_error=local_owner?l_rsp_error:nse[0];
 assign l_rsp_ready=cn_busy&&local_owner&&cn_rsp_ready;
 assign nsr[0]=cn_busy&&!local_owner&&cn_rsp_ready;
 // 过程边界：always_ff @(posedge clk)begin。
 // 本过程的赋值优先级按分支书写顺序决定；跨过程信号应沿显式接口追踪。
 always_ff @(posedge clk)begin
  // 复位相关判断：rst；分支方向由信号极性与取反表达式决定。
  if(rst)begin cn_busy<=0;local_owner<=0;end
  else begin
   // 握手/背压判断：cn_req_valid&&cn_req_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(cn_req_valid&&cn_req_ready)begin cn_busy<=1;local_owner<=local_select;end
   // 握手/背压判断：cn_rsp_valid&&cn_rsp_ready。
   // 只有原条件成立才推进本分支，未被接收的事务需保留其负载及归属。
   if(cn_rsp_valid&&cn_rsp_ready)cn_busy<=0;
  end
 end
 soc_graph_executor #(.PROGRAM_ADDR_BITS(PROGRAM_ADDR_BITS)) executor(
  .clk,.rst,.req_valid(cn_req_valid&&!cn_busy&&local_select),.req_ready(l_req_ready),
  .req_addr(cn_req_addr[7:0]),.req_write(cn_req_write),.req_wdata(cn_req_wdata),.req_wstrb(cn_req_wstrb),
  .rsp_valid(l_rsp_valid),.rsp_ready(l_rsp_ready),.rsp_rdata(l_rsp_data),.rsp_error(l_rsp_error),
  .m_req_valid(g_req_valid),.m_req_ready(g_req_ready),.m_req_addr(g_req_addr),.m_req_wdata(g_req_data),
  .m_req_write(g_req_write),.m_req_wstrb(g_req_strb),.m_rsp_valid(g_rsp_valid),.m_rsp_ready(g_rsp_ready),
  .m_rsp_rdata(g_rsp_data),.m_rsp_error(g_rsp_error),.busy(graph_busy),.poison(graph_poison),.input_consumed(graph_input_consumed));
 assign nv={g_req_valid&&g_req_addr[28],cn_req_valid&&!cn_busy&&!local_select};
 assign na={g_req_addr,{16'd0,cn_req_addr}};assign nd={g_req_data,cn_req_wdata};
 assign bv={g_req_valid&&!g_req_addr[28],cb_req_valid};assign ba={g_req_addr,cb_req_addr};assign bd={g_req_data,cb_req_wdata};
 assign g_req_ready=g_req_addr[28]?nr[1]:br[1];
 assign g_rsp_valid=g_req_addr[28]?nsv[1]:bsv[1];
 assign g_rsp_data=g_req_addr[28]?nsd[1]:bsd[1];
 assign g_rsp_error=g_req_addr[28]?nse[1]:bse[1];
 assign nsr[1]=g_rsp_ready&&g_req_addr[28];assign bsr={g_rsp_ready&&!g_req_addr[28],cb_rsp_ready};
 assign cb_req_ready=br[0];assign cb_rsp_valid=bsv[0];assign cb_rsp_rdata=bsd[0];assign cb_rsp_error=bse[0];
 assign n_req_addr=unused_n_full_addr[15:0];
 soc_mmio_2m_registered npu_arb(
  .clk,.rst,.s_req_valid(nv),.s_req_ready(nr),.s_req_addr(na),.s_req_wdata(nd),
  .s_req_write({g_req_write,cn_req_write}),.s_req_fetch(2'b0),.s_req_wstrb({g_req_strb,cn_req_wstrb}),
  .s_rsp_valid(nsv),.s_rsp_ready(nsr),.s_rsp_rdata(nsd),.s_rsp_error(nse),
  .m_req_valid(n_req_valid),.m_req_ready(n_req_ready),.m_req_addr(unused_n_full_addr),.m_req_wdata(n_req_wdata),
  .m_req_write(n_req_write),.m_req_fetch(n_unused_fetch),.m_req_wstrb(n_req_wstrb),
  .m_rsp_valid(n_rsp_valid),.m_rsp_ready(n_rsp_ready),.m_rsp_rdata(n_rsp_rdata),.m_rsp_error(n_rsp_error));
 soc_mmio_2m_registered board_arb(
  .clk,.rst,.s_req_valid(bv),.s_req_ready(br),.s_req_addr(ba),.s_req_wdata(bd),
  .s_req_write({g_req_write,cb_req_write}),.s_req_fetch({1'b0,cb_req_fetch}),.s_req_wstrb({g_req_strb,cb_req_wstrb}),
  .s_rsp_valid(bsv),.s_rsp_ready(bsr),.s_rsp_rdata(bsd),.s_rsp_error(bse),
  .m_req_valid(b_req_valid),.m_req_ready(b_req_ready),.m_req_addr(b_req_addr),.m_req_wdata(b_req_wdata),
  .m_req_write(b_req_write),.m_req_fetch(b_req_fetch),.m_req_wstrb(b_req_wstrb),
  .m_rsp_valid(b_rsp_valid),.m_rsp_ready(b_rsp_ready),.m_rsp_rdata(b_rsp_rdata),.m_rsp_error(b_rsp_error));
endmodule
