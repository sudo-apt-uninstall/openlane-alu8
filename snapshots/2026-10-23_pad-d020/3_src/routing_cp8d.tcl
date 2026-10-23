# ----------------------------------------------------------------------------
# OpenROAD Routing Script for SCL 0.8um Process
# ----------------------------------------------------------------------------

# Read design files

read_liberty $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lib/cp8d_core_typ.lib

read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.tech/openlane/digital_cp8d/lef/tech_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/core_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/pads_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/corner_cp8d.lef

# Read the CTS DEF
read_def "$::env(DESIGN_DIR)/runs/RUN/results/cts/$::env(DESIGN_NAME)_plcts.def"

# IMPORTANT NOTE: If the circuit is combinational, the placement DEF can be used 
# for routing, and the 'cts_cp8d.tcl' script can be skipped.
# 
# To skip the CTS step:
# 1. Comment out the 'read_def ... cts ...' line above.
# 2. Uncomment the 'read_def ... placement ...' line below.
# 3. Skip the step: run_openroad_script $::env(DESIGN_DIR)/3_src/cts_cp8d.tcl
#
# read_def "$::env(DESIGN_DIR)/runs/RUN/results/placement/$::env(DESIGN_NAME)_pl.def"


make_tracks metal1 -x_offset 0 -x_pitch 3.7 -y_offset 0 -y_pitch 3.7
make_tracks metal2 -x_offset 1.95 -x_pitch 3.9 -y_offset 0 -y_pitch 3.9

# Pin Placement
place_pins -hor_layers {metal1} -ver_layers {metal2}

# Routing layer settings
set_global_routing_layer_adjustment metal1 0
set_global_routing_layer_adjustment metal2 0

# Restricted layers
set_routing_layers -signal metal1-metal2 -clock metal1-metal2

# Global routing
global_route -allow_congestion -verbose

# ----------------------------------------------------------------------------
# FIXED: Detailed routing (Removed positional argument and backslash)
# ----------------------------------------------------------------------------
detailed_route \
    -output_drc "$::env(DESIGN_DIR)/runs/RUN/results/routing/drc.rpt" \
    -verbose 1

# Write outputs
 write_def "$::env(DESIGN_DIR)/runs/RUN/results/routing/$::env(DESIGN_NAME)_rt.def"
#write_def "$::env(DESIGN_DIR)/5_klayout/$::env(DESIGN_NAME)_rt.def"

 write_verilog -include_pwr_gnd "$::env(DESIGN_DIR)/runs/RUN/results/routing/$::env(DESIGN_NAME)_rt_pwr.v"
#write_verilog -include_pwr_gnd "$::env(DESIGN_DIR)/5_klayout/$::env(DESIGN_NAME)_rt_pwr.v"

write_verilog -remove_cells {FILLER1 FILLER2 FILLER3 FILLER4 FILLER5 FILLER6 CORNER} "$::env(DESIGN_DIR)/runs/RUN/results/routing/$::env(DESIGN_NAME)_rt_sim.v"

