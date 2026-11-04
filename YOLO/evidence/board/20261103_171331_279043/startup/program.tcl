cfg_set_tcl_break -flag true
cfg_connect -ip 127.0.0.1 -port 65450
cfg_set_cable_property -index 0 -freq 5MHz
cfg_scan_chain
cfg_assign_file -file {D:/workspace/riscv-fpga-soc/build/yrev27_05/bitstream/project/prj_tasks/pnr_1/generate_bitstream/soc_board_camera_top.sbit} -device_index 0
cfg_set_device_property -device_index 0 -program 1
cfg_program -device_index 0
cfg_read_device_property -mode 3 -device_index 0
cfg_disconnect
