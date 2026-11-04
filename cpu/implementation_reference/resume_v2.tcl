open_project {D:/workspace/riscv-fpga-soc/work/rv32_ila130_20261103_01/tag_split117_01/ila_synth.pds}
launch_tasks [get_tasks {syn_1}] -to_action compile
wait_on_tasks [get_tasks {syn_1}] -to_action compile
launch_tasks [get_tasks {syn_1}] -to_action synthesize
wait_on_tasks [get_tasks {syn_1}] -to_action synthesize
add_fic {D:/workspace/riscv-fpga-soc/work/rv32_ila130_20261103_01/tag_split117_01/ila117.fic} -copy
dev_map -force_to_run
wait_on_tasks [get_tasks {pnr_1}] -to_action dev_map
save_project
puts "DEV_MAP_DONE_INSPECT_LOG_AND_ADF_BEFORE_CONTINUING"

# STAGE 2 TEMPLATE: run only after map success AND evidence of actual debug insertion.
# Verify these expected output filenames against actual stage-1 logs before executing.
set_option -options {max_threads 4 max_parallel_jobs 1} [current_project]
set_option -options {strategy 0} [get_tasks pnr_1]
set_option -options {dc_duplication Global refineplacement_iteration 20 planning_before_place Enable} [get_actions place -of_objects [get_tasks pnr_1]]
place -input_db_file {D:/workspace/riscv-fpga-soc/work/rv32_ila130_20261103_01/tag_split117_01/prj_tasks/pnr_1/device_map/rv32_coremark_top_boot_map.adf} -force_to_run
wait_on_tasks [get_tasks {pnr_1}] -to_action place
route -input_db_file {D:/workspace/riscv-fpga-soc/work/rv32_ila130_20261103_01/tag_split117_01/prj_tasks/pnr_1/device_map/rv32_coremark_top_boot_map.adf} -input_place_db_file {D:/workspace/riscv-fpga-soc/work/rv32_ila130_20261103_01/tag_split117_01/prj_tasks/pnr_1/place_route/rv32_coremark_top_boot_plc.adf} -route_mode normal -slack_weight 90 -pin_cost_increasing_speed 300 -force_to_run
wait_on_tasks [get_tasks {pnr_1}] -to_action route
route_optimize -input_db_file {D:/workspace/riscv-fpga-soc/work/rv32_ila130_20261103_01/tag_split117_01/prj_tasks/pnr_1/place_route/rv32_coremark_top_boot_route.adf} -fix_hold_violation_in_route TRUE -force_to_run
wait_on_tasks [get_tasks {pnr_1}] -to_action route_optimize
set_option -options {max_threads 2} [current_project]
report_timing -input_db_file {D:/workspace/riscv-fpga-soc/work/rv32_ila130_20261103_01/tag_split117_01/prj_tasks/pnr_1/place_route/rv32_coremark_top_boot_pnr.adf} -nworst 1 -max_path 10000 -input_pins TRUE -force_to_run
wait_on_tasks [get_tasks {pnr_1}] -to_action report_timing
save_project
puts "ROUTE_DONE_INSPECT_TIMING_AND_DEBUG_PRESENCE_BEFORE_BITGEN"

puts ILA117_NATIVE_FLOW_COMPLETE
