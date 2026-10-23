read_liberty $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lib/cp8d_core_typ.lib

read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.tech/openlane/digital_cp8d/lef/tech_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/core_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/pads_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/corner_cp8d.lef

read_db "$::env(DESIGN_DIR)/runs/RUN/results/placement/$::env(DESIGN_NAME)_plcts.odb"

set_cmd_units -time ns -capacitance pF -resistance kOhm -voltage V -current mA

detailed_placement

set ::env(FP_FILL_CELL) "FILLER1 FILLER2 FILLER3 FILLER4 FILLER5 FILLER6"
filler_placement -prefix FILLER [list "FILLER1" "FILLER2" "FILLER3" "FILLER4" "FILLER5" "FILLER6"]

write_db  "$::env(DESIGN_DIR)/runs/RUN/results/cts/$::env(DESIGN_NAME)_plcts.odb"
write_def "$::env(DESIGN_DIR)/runs/RUN/results/cts/$::env(DESIGN_NAME)_plcts.def"
