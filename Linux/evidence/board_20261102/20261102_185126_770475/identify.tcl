cfg_set_tcl_break -flag true
cfg_connect -ip 127.0.0.1 -port 56946
cfg_set_cable_property -index 0 -freq 5MHz
cfg_scan_chain
cfg_read_device_property -mode 0 -device_index 0
cfg_disconnect
puts ID_COMPLETE
