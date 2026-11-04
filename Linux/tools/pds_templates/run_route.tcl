open_project {@IMPL@/project/gui27.pds}
set_option -options {max_threads 4 max_parallel_jobs 1} [current_project]
set_option -options {route_mode normal} [get_actions route -of_objects [get_tasks pnr_1]]
launch_tasks [get_tasks {pnr_1}] -to_action route
wait_on_tasks [get_tasks {pnr_1}] -to_action route
set_option -options {fix_hold_violation_in_route true} [get_actions route_optimize -of_objects [get_tasks pnr_1]]
launch_tasks [get_tasks {pnr_1}] -to_action route_optimize
wait_on_tasks [get_tasks {pnr_1}] -to_action route_optimize
set_option -options {nworst 5 max_path 100 input_pins true} [get_actions report_timing -of_objects [get_tasks pnr_1]]
launch_tasks [get_tasks {pnr_1}] -to_action report_timing
wait_on_tasks [get_tasks {pnr_1}] -to_action report_timing
puts "LINUX_GUI_NATIVE_ROUTE_COMPLETE"
