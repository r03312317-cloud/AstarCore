cfg_set_tcl_break -flag true
cfg_connect -ip 127.0.0.1 -port 56946
cfg_set_cable_property -index 0 -freq 5MHz
cfg_scan_chain
cfg_assign_file -file {D:/workspace/riscv-fpga-soc/Soc_linux/board_runs/core01_board_20261102_01/operator/bitstream/soc_linux_compact.sbit} -device_index 0
cfg_set_device_property -device_index 0 -program 1
cfg_program -device_index 0
cfg_scan_chain
cfg_disconnect
puts PROGRAM_COMPLETE
