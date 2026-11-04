cd {D:/workspace/riscv-fpga-soc/build/yrev27_05/bitstream}
create_project {D:/workspace/riscv-fpga-soc/build/yrev27_05/bitstream/project/soc_board_camera_top.pds} -project_type rtl -syn_tool ads -in_process
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
set_option -options {max_threads 2 max_parallel_jobs 1} [current_project]
file copy {D:/workspace/riscv-fpga-soc/build/yrev27_05/bitstream/define.vh} {D:/workspace/riscv-fpga-soc/build/yrev27_05/bitstream/project/define.vh}
file copy {D:/workspace/riscv-fpga-soc/build/yrev27_05/bitstream/coremark-itcm.mem} {D:/workspace/riscv-fpga-soc/build/yrev27_05/bitstream/project/coremark-itcm.mem}
file copy {D:/workspace/riscv-fpga-soc/build/yrev27_05/bitstream/coremark-dtcm.mem} {D:/workspace/riscv-fpga-soc/build/yrev27_05/bitstream/project/coremark-dtcm.mem}
add_constraint {D:/workspace/riscv-fpga-soc/build/yrev27_05/snapshot/native_pds25_03/inputs/stage/board/soc_board_camera.fdc}
add_constraint {D:/workspace/riscv-fpga-soc/build/yrev27_05/snapshot/native_pds25_03/inputs/stage/ipcore/soc_ddr800/pnr/soc_ddr800.rcf}
add_constraint {D:/workspace/riscv-fpga-soc/build/yrev27_05/snapshot/native_pds25_03/constraints/hdmi_tx_neario_01.fdc}
gen_bit_stream -input_db_file {D:/workspace/riscv-fpga-soc/build/yrev27_05/route/project/prj_tasks/pnr_1/place_route/soc_board_camera_top_pnr.adf} -scbv {High Voltage} -compress_bitstream TRUE -optimize_compress TRUE -disable_cyclic_redundancy_checking FALSE -write_drm_data TRUE -force_to_run
puts "UNIFIED_BITSTREAM_COMPLETE"
flush stdout
