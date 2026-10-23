
             
read_liberty $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lib/cp8d_core_typ.lib

read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.tech/openlane/digital_cp8d/lef/tech_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/core_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/pads_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/corner_cp8d.lef

read_verilog $::env(DESIGN_DIR)/4A_synthesis_netlist/$::env(DESIGN_NAME)_sys.v


link_design $::env(DESIGN_TOP_CELL_NAME)

# Read SDC if it exists  
if { [file exists $::env(DESIGN_DIR)/check_stdcells/4A_synthesis_netlist/$::env(DESIGN_NAME).sdc] } {
    read_sdc $::env(DESIGN_DIR)/check_stdcells/4A_synthesis_netlist/$::env(DESIGN_NAME).sdc
}

# The manual command that worked in your terminal
# Using 'eval' ensures the list from DIE_AREA is parsed correctly
initialize_floorplan -site $::env(PLACE_SITE) -die_area "$::env(DIE_AREA)" -core_area "$::env(CORE_AREA)"

# ---------------------------------------------------------
set block [[ord::get_db_block] getRows]
set count 0
foreach row $block {
    if { [expr $count % 2] != 0 } {
        # Delete every odd-numbered row to create a 1-row gap
        odb::dbRow_destroy $row
    }
    incr count
}
puts "Custom Row Modification: Removed alternating rows to prevent overlaps."
# ---------------------------------------------------------

# 4. Save the result
set output_def "$::env(DESIGN_DIR)/runs/RUN/results/floorplan/$::env(DESIGN_NAME).def"


write_def $output_def


puts "Success: Floorplan saved to results folder."


