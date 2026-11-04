cd {D:/workspace/riscv-fpga-soc/build/yrev27_05/route}
create_project {D:/workspace/riscv-fpga-soc/build/yrev27_05/route/project/soc_board_camera_top.pds} -project_type rtl -syn_tool ads -in_process
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
set_option -options {max_threads 2 max_parallel_jobs 1} [current_project]
file copy {D:/workspace/riscv-fpga-soc/build/yrev27_05/route/define.vh} {D:/workspace/riscv-fpga-soc/build/yrev27_05/route/project/define.vh}
file copy {D:/workspace/riscv-fpga-soc/build/yrev27_05/route/coremark-itcm.mem} {D:/workspace/riscv-fpga-soc/build/yrev27_05/route/project/coremark-itcm.mem}
file copy {D:/workspace/riscv-fpga-soc/build/yrev27_05/route/coremark-dtcm.mem} {D:/workspace/riscv-fpga-soc/build/yrev27_05/route/project/coremark-dtcm.mem}
add_constraint {D:/workspace/riscv-fpga-soc/build/yrev27_05/snapshot/native_pds25_03/inputs/stage/board/soc_board_camera.fdc}
add_constraint {D:/workspace/riscv-fpga-soc/build/yrev27_05/snapshot/native_pds25_03/inputs/stage/ipcore/soc_ddr800/pnr/soc_ddr800.rcf}
add_constraint {D:/workspace/riscv-fpga-soc/build/yrev27_05/snapshot/native_pds25_03/constraints/hdmi_tx_neario_01.fdc}
dev_map -input_db_file {D:/workspace/riscv-fpga-soc/build/yrev27_05/synthesis/project/prj_tasks/syn_1/synthesize/soc_board_camera_top_syn.adf} -force_to_run
pnr -logic_optimize_lut6d TRUE -gplace_seed 31 -mode normal -max_ctrl_chain_length 64 -fix_hold_violation_in_route TRUE -fix_hold_violation_threshold_for_clock_path_cross_srb 300 -fix_hold_violation_threshold_for_clk_tree 50 -max_hold_violated_paths_num 10000 -dump_router_congestion_plot FALSE -force_to_run
puts "UNIFIED_ROUTE_COMPLETE"
flush stdout
