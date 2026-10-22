yosys read_liberty -lib $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lib/cp8d_core_typ.lib
yosys read_verilog -sv $::env(DESIGN_DIR)/1_RTL/$::env(DESIGN_NAME).v
yosys hierarchy -top $::env(DESIGN_TOP_CELL_NAME)
yosys opt; yosys proc;  yosys fsm; yosys opt; yosys memory; yosys opt
yosys techmap; yosys opt;
yosys dfflibmap -liberty $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lib/cp8d_core_typ.lib
yosys abc -liberty $::env(PDK_ROOT)/$::env(PDK)/libs.ref/digital_cp8d/lib/cp8d_core_typ.lib
yosys opt; yosys clean;

# --- tie-cell insertion ---
yosys setundef -zero
yosys hilomap -hicell VDDCON TIEHI -locell VSSCON TIELO
yosys opt_clean
# ---------------------------

yosys write_verilog $::env(DESIGN_DIR)/4A_synthesis_netlist/$::env(DESIGN_NAME)_sys.v
yosys write_verilog $::env(DESIGN_DIR)/runs/RUN/results/synthesis/$::env(DESIGN_NAME)_sys.v
