# Load the technology and cell physical data 
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.tech/openlane/digital_cp8d/lef/tech_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/core_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/pads_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/corner_cp8d.lef

# Load the liberty files
read_liberty $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lib/cp8d_core_typ.lib

# Read the gate-level netlist (the .v file used to generate your DEF)
read_verilog "$::env(DESIGN_DIR)/runs/RUN/results/routing/$::env(DESIGN_NAME)_rt_sim.v"

# Set the top module name
link_design $::env(DESIGN_TOP_CELL_NAME)

# Read the parasitics you just generated
read_spef "$::env(DESIGN_DIR)/runs/RUN/results/spef/$::env(DESIGN_NAME)_rt.spef"

create_clock -name CLK -period $::env(CLOCK_PERIOD) [get_ports clk]

# Ensure target folder exists before writing reports
file mkdir "$::env(DESIGN_DIR)/runs/RUN/results/sta"

# Generate reports (Writing them inside the 'sta' directory keeps things clean)
report_checks -path_delay min_max -format full_clock_expanded > "$::env(DESIGN_DIR)/runs/RUN/results/sta/timing_report.txt"
report_tns > "$::env(DESIGN_DIR)/runs/RUN/results/sta/tns_report.txt"
report_wns > "$::env(DESIGN_DIR)/runs/RUN/results/sta/wns_report.txt"

write_sdf "$::env(DESIGN_DIR)/runs/RUN/results/sta/$::env(DESIGN_NAME)_rt.sdf"
