
# ----------------------------------------------------------------------------
# OpenROAD Routing Script for SCL 0.8um for CTS
# ----------------------------------------------------------------------------

read_liberty $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lib/cp8d_core_typ.lib

read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.tech/openlane/digital_cp8d/lef/tech_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/core_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/pads_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/corner_cp8d.lef

read_db "$::env(DESIGN_DIR)/runs/RUN/results/placement/$::env(DESIGN_NAME)_plcts.odb"

# Define the clock constraints manually since characterization failed
set_cmd_units -time ns -capacitance pF -resistance kOhm -voltage V -current mA

# Create the clock tree
create_clock -name CLK -period $::env(CLOCK_PERIOD) [get_ports clk]
set_propagated_clock [all_clocks]

# We use the buffers you identified in your SCL800 library
clock_tree_synthesis -root_buf INVR00 -buf_list "INVR01 INVR02 INVR03 INVR04" -sink_clustering_enable


# Legalize the newly inserted buffers
#hold_slack_margin 0.1
#setup_slack_margin 0.0

repair_clock_nets

detailed_placement

set ::env(FP_FILL_CELL) "FILLER1 FILLER2 FILLER3 FILLER4 FILLER5 FILLER6"
filler_placement -prefix FILLER [list "FILLER1" "FILLER2" "FILLER3" "FILLER4" "FILLER5" "FILLER6"]

# Save the result
write_db  "$::env(DESIGN_DIR)/runs/RUN/results/cts/$::env(DESIGN_NAME)_plcts.odb"
write_def "$::env(DESIGN_DIR)/runs/RUN/results/cts/$::env(DESIGN_NAME)_plcts.def"
