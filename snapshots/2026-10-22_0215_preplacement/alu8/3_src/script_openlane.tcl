run_yosys_script $::env(DESIGN_DIR)/3_src/yosys_script.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/floorplan_cp8d.tcl

run_openroad_script $::env(DESIGN_DIR)/3_src/pdn_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/placement_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/cts_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/routing_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/rcx_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/run_sta.tcl
