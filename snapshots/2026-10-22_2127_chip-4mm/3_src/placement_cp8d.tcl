read_liberty $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lib/cp8d_core_typ.lib

read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.tech/openlane/digital_cp8d/lef/tech_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/core_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/pads_cp8d.lef
read_lef $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lef/corner_cp8d.lef


# Read the floorplanned DEF
read_def "$::env(DESIGN_DIR)/runs/RUN/results/floorplan/$::env(DESIGN_NAME)_pdn.def"

# Optimization 1: Clear unneeded tool memory and graphics if enabled
catch {gui::clear_highlights}

# Optimization 2: Explicitly set thread constraints to prevent memory thrashing
set_thread_count 2

# Run Global Placement with a relaxed density constraint to reduce bin complexity
global_placement -density $::env(PL_TARGET_DENSITY)

# Optimization 3: Run detailed placement with Max Displacement to bound the search space
#detailed_placement -max_displacement {50 50}
detailed_placement

# Verify validity
 check_placement -verbose

# Write outputs
write_def "$::env(DESIGN_DIR)/runs/RUN/results/placement/$::env(DESIGN_NAME)_pl.def"
puts "Success: Manual placement reached."

write_db "$::env(DESIGN_DIR)/runs/RUN/results/placement/$::env(DESIGN_NAME)_plcts.odb"

