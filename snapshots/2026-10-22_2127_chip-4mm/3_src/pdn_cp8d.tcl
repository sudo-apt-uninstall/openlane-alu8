# pdn_cp8d.tcl for VDD & GROUND straps

read_liberty $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lib/cp8d_core_typ.lib

read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.tech/openlane/digital_cp8d/lef/tech_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/core_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/pads_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/corner_cp8d.lef


#$# read_def $::env(DESIGN_DIR)/runs/RUN/results/floorplan/$::env(DESIGN_NAME)_io.def

read_def "$::env(DESIGN_DIR)/runs/RUN/results/floorplan/$::env(DESIGN_NAME).def"

add_global_connection -net VDD -pin_pattern VDD -power               
                     
add_global_connection -net GROUND -pin_pattern GROUND -ground
                     
                      
                      
global_connect

set_voltage_domain -name CORE -power VDD -ground GROUND
define_pdn_grid -name "Core_1" -voltage_domain CORE -pins "metal2" 
set_pdnsim_net_voltage -net VDD -voltage 5.0
set_pdnsim_net_voltage -net GROUND -voltage 0.0
#add_pdn_ring -grid "Core" -layers {"metal1" "metal2"} -widths "7 7" -spacings "5 5" -nets "GROUND VDD" -core_offsets "5 5" -connect_to_pads -connect_to_pad_layers {"metal2" "metal1"} 

add_pdn_stripe -grid "Core_1" -layer metal1 -width 7.0 -followpins -extend_to_core_ring 

#add_pdn_stripe -grid "Core_1" -layer metal2 -width 2.5 -pitch 8000 -offset 10 -extend_to_core_ring 

#add_pdn_stripe -grid "Core_1" -layer metal2 -width 2.5 -pitch 10000 -offset 10 -extend_to_core_ring 
add_pdn_connect -grid "Core_1" -layers {"metal1" "metal2"}

#route_manual -layers metal2 -rects {1201 1 4695 83} -net VDD

add_pdn_ring -grid "Core_1" -layer {"metal1" "metal2"} -widths "30 30" -spacings "3 3" -core_offsets "30 30"

#add_pdn_connect -grid "Core_1" -layers {"metal1" "metal2"}  
###################################add_pdn_connect -grid "Core" -layers {"metal1" "metal2"}
#add_pdn_ring -grid std_cell_grid -layers {metal1 metal2} -widths 7.0 -spacings 5.0 -core_offsets 3.0
#add_pdn_ring -grid std_cell_grid -layer {"metal1" "metal2"} -widths "7 7" -spacings "5 5" -core_offsets "3 3" -add_connect -connect_to_pads
#add_pdn_connect -grid std_cell_grid -layers {metal1 metal2}
#add_pdn_connect -grid std_cell_grid -layers {metal1 metal2}

pdngen

# Corrected namespace syntax (no spaces)

write_def $::env(DESIGN_DIR)/runs/RUN/results/floorplan/$::env(DESIGN_NAME)_pdn.def
