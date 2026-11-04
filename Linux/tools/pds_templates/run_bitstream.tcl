open_project {@IMPL@/project/gui27.pds}
set_option -options {max_threads 2 max_parallel_jobs 1} [current_project]
set_option -options {input_db_file {@IMPL@/project/prj_tasks/pnr_1/place_route/soc_linux_gui_top_pnr.adf} compress_bitstream true optimize_compress true scbv {High Voltage}} [get_actions gen_bit_stream -of_objects [get_tasks pnr_1]]
launch_tasks [get_tasks {pnr_1}] -to_action gen_bit_stream
wait_on_tasks [get_tasks {pnr_1}] -to_action gen_bit_stream
puts "LINUX_GUI_NATIVE_BITSTREAM_COMPLETE"
