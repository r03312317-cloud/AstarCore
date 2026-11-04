open_project {@IMPL@/project/gui27.pds}
set_option -options {max_threads 2 max_parallel_jobs 1} [current_project]
set_option -options {strategy 0} [get_tasks pnr_1]
set_option -options {gplace_seed 31} [get_actions pnr -of_objects [get_tasks pnr_1]]
set_option -options {mode normal logic_optimize_lut6d true} [get_actions place -of_objects [get_tasks pnr_1]]
launch_tasks [get_tasks {pnr_1}] -to_action place
wait_on_tasks [get_tasks {pnr_1}] -to_action place
puts "LINUX_GUI_NATIVE_PLACE_COMPLETE"
