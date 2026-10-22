#!/usr/bin/env bash
#
# signoff.sh -- headless CDL + GDS + DRC + LVS for alu8 on SCL CP8D.
#
# WHY THIS EXISTS
#   signoff/cdl_gds_script.source (SCL's template, retargeted to alu8) builds the
#   CDL and the GDS and then runs `klayout -e`, which OPENS THE GUI. It runs
#   neither DRC nor LVS -- both were done by hand, which is why the first signoff
#   produced no reproducible command trail. This script closes that gap: same two
#   generation steps, then both checks in batch, then a verdict on stdout.
#
# STATUS
#   The CDL and GDS sections are lifted verbatim from cdl_gds_script.source and
#   are known-good. The DRC and LVS sections have NOT been executed yet -- the
#   KLayout decks are PDK files and are not in this repository, so the names of
#   the variables they expect via -rd could not be confirmed from here. The
#   script therefore inspects the decks first and tells you exactly what they
#   reference instead of guessing. Confirm once, then it is reproducible forever.
#
# USAGE
#   chmod +x signoff.sh         # git stores this 100644
#   sclenv                      # sets PDK_ROOT, KLAYOUT_PATH, OPENLANE_PATH
#   ./signoff.sh                # defaults to PROJECT_NAME=alu8, tag RUN
#   DRC_ONLY=1 ./signoff.sh     # skip LVS
#
set -euo pipefail

PROJECT_NAME="${PROJECT_NAME:-alu8}"
DESIGN_NAME="${DESIGN_NAME:-alu8}"
DESIGN_TOP_CELL_NAME="${DESIGN_TOP_CELL_NAME:-alu8}"
RUN_TAG="${RUN_TAG:-RUN}"

: "${OPENLANE_PATH:?run sclenv first -- OPENLANE_PATH is unset}"
: "${PDK_ROOT:?run sclenv first -- PDK_ROOT is unset}"
: "${KLAYOUT_PATH:?run sclenv first -- KLAYOUT_PATH is unset}"

PROJ="$OPENLANE_PATH/designs/project_scl_cp8d/$PROJECT_NAME"
KL="$PROJ/5_klayout"
OUT="$KL/lvs_drc"
ROUTING="$PROJ/runs/$RUN_TAG/results/routing"

DRC_DECK="${DRC_DECK:-$KLAYOUT_PATH/drc/drc.lydrc}"
LVS_DECK="${LVS_DECK:-$KLAYOUT_PATH/lvs/lvs.lylvs}"

say() { printf '\n=== %s\n' "$*"; }
need() {
    [ -s "$1" ] || { echo "MISSING OR EMPTY: $1" >&2; exit 1; }
    printf '  OK %9d  %s\n' "$(stat -c%s "$1")" "$1"
}

# -----------------------------------------------------------------------------
say "0. inputs"
need "$ROUTING/${DESIGN_NAME}_rt_pwr.v"      # supply pins -> this is the LVS source
need "$ROUTING/${DESIGN_NAME}_rt.def"
need "$OUT/core_iolib_cp8d.cdl"              # PDK-derived, never committed here

# A KLayout report records the deck it ran under <generator>. If that path is not
# the PDK you built against, DRC silently checked a different process.
echo "  PDK_ROOT   = $PDK_ROOT"
echo "  DRC_DECK   = $DRC_DECK"

# -----------------------------------------------------------------------------
say "1. CDL  (verilog2spice.py, from _rt_pwr.v -- NOT _rt_sim.v)"
cd "$KL/script"
python3 verilog2spice.py \
    -spice   "$OUT/core_iolib_cp8d.cdl" \
    -verilog "$ROUTING/${DESIGN_NAME}_rt_pwr.v" \
    -output  "$OUT/${DESIGN_TOP_CELL_NAME}.cdl" \
    -pos_pwr VDD \
    -neg_pwr GROUND -delimiter
need "$OUT/${DESIGN_TOP_CELL_NAME}.cdl"

# -----------------------------------------------------------------------------
say "2. GDS  (def2gds.py)"
klayout -b -zz \
    -rd in_def="$ROUTING/${DESIGN_NAME}_rt.def" \
    -rd out_gds="$OUT/${DESIGN_TOP_CELL_NAME}.gds" \
    -r def2gds.py
need "$OUT/${DESIGN_TOP_CELL_NAME}.gds"

# -----------------------------------------------------------------------------
say "3. deck inspection -- confirm the -rd names before trusting steps 4 and 5"
for deck in "$DRC_DECK" "$LVS_DECK"; do
    [ -r "$deck" ] || { echo "  deck not readable: $deck"; continue; }
    echo "  $deck references:"
    grep -oE '\$[A-Za-z_][A-Za-z0-9_]*' "$deck" | sort -u | sed 's/^/    /'
done
echo "  If the names below do not appear above, override them:"
echo "    DRC_IN=... DRC_OUT=... LVS_IN=... LVS_SCHEMATIC=... LVS_OUT=..."

DRC_IN="${DRC_IN:-input}"
DRC_OUT="${DRC_OUT:-report}"
LVS_IN="${LVS_IN:-input}"
LVS_SCHEMATIC="${LVS_SCHEMATIC:-schematic}"
LVS_OUT="${LVS_OUT:-target_netlist}"

# -----------------------------------------------------------------------------
say "4. DRC"
klayout -b -zz \
    -rd "${DRC_IN}=$OUT/${DESIGN_TOP_CELL_NAME}.gds" \
    -rd "${DRC_OUT}=$OUT/scl_drc.txt" \
    -r "$DRC_DECK"

if [ -s "$OUT/scl_drc.txt" ]; then
    # The report is XML. Each violation is one <item>.
    n=$(grep -c '<item>' "$OUT/scl_drc.txt" || true)
    printf '  DRC items: %s   (expected 3 boron-width on INVR00 as of 2026-10-22)\n' "$n"
    [ "$n" -eq 0 ] && echo "  DRC CLEAN" || echo "  DRC NOT CLEAN"
else
    echo "  no DRC report produced -- the -rd names above are probably wrong"
fi

# -----------------------------------------------------------------------------
if [ "${DRC_ONLY:-0}" = "1" ]; then
    say "LVS skipped (DRC_ONLY=1)"; exit 0
fi

say "5. LVS"
klayout -b -zz \
    -rd "${LVS_IN}=$OUT/${DESIGN_TOP_CELL_NAME}.gds" \
    -rd "${LVS_SCHEMATIC}=$OUT/${DESIGN_TOP_CELL_NAME}.cdl" \
    -rd "${LVS_OUT}=$OUT/${DESIGN_TOP_CELL_NAME}.lvsdb" \
    -r "$LVS_DECK"
need "$OUT/${DESIGN_TOP_CELL_NAME}.lvsdb"

# The LVS verdict lives inside the .lvsdb, not in a text file. KLayout's Netlist
# Browser renders it; from the shell the match flag is the only cheap signal.
if grep -qi 'xref.*mismatch\|not matched' "$OUT/${DESIGN_TOP_CELL_NAME}.lvsdb"; then
    echo "  LVS: mismatches present -- open in KLayout Netlist Browser"
else
    echo "  LVS: no mismatch markers found (open the Netlist Browser to confirm)"
fi

say "DONE"
echo "  artefacts in $OUT"
