create_project {@IMPL@/project/gui27.pds} -project_type rtl -syn_tool ads -in_process
set_option -options {max_threads 2 max_parallel_jobs 1} [current_project]
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
add_constraint {@IMPL@/inputs/soc_linux_gui.fdc}
add_constraint {@IMPL@/inputs/soc_ddr800.rcf}
set_option -options {input_db_file {@IMPL@/inputs/design_syn.adf}} [get_actions dev_map -of_objects [get_tasks pnr_1]]
launch_tasks [get_tasks {pnr_1}] -to_action dev_map
wait_on_tasks [get_tasks {pnr_1}] -to_action dev_map
puts "LINUX_GUI_NATIVE_MAP_COMPLETE"
