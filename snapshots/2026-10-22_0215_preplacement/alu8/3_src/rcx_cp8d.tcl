# ----------------------------------------------------------------------------
# OpenROAD Routing Script for SCL 0.8um Process
# ----------------------------------------------------------------------------

# Read design files

read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.tech/openlane/digital_cp8d/lef/tech_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/core_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/corner_cp8d.lef

read_def "$::env(DESIGN_DIR)/runs/RUN/results/routing/$::env(DESIGN_NAME)_rt.def"

define_process_corner -ext_model_index 0 $::env(PDK_ROOT)/$::env(PDK)/libs.tech/openrcx/scl800.rcx.lib

extract_parasitics -ext_model_file $::env(PDK_ROOT)/$::env(PDK)/libs.tech/openrcx/scl800.rcx.lib

file mkdir "$::env(DESIGN_DIR)/runs/RUN/results/spef"

write_spef "$::env(DESIGN_DIR)/runs/RUN/results/spef/$::env(DESIGN_NAME)_rt.spef"
