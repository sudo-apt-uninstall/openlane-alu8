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
# STATUS 2026-10-22
#   Deck paths and the report mechanism are now MEASURED on W0, not guessed:
#
#     $KLAYOUT_PATH/tech/drc/drc.lydrc      <- note the tech/ level
#     $KLAYOUT_PATH/tech/lvs/lvs.lylvs
#
#   and the DRC report is written to ./scl_drc.txt RELATIVE TO THE CURRENT
#   DIRECTORY. There is no -rd override for it. An earlier run proved this the
#   hard way by depositing a report inside the PDK tree, because that happened
#   to be the CWD. This script therefore runs DRC from a working directory of
#   its own and moves the report out afterwards.
#
#   Still unconfirmed: whether the decks accept an input layout via -rd at all,
#   or only operate on the layout open in the GUI. Step 3 inspects them and
#   prints the variables they actually reference. If DRC produces no report,
#   that is the thing to read.
#
# USAGE
#   chmod +x signoff.sh         # git stores this 100644
#   sclenv                      # sets PDK_ROOT, KLAYOUT_PATH, OPENLANE_PATH
#   ./signoff.sh                # defaults to PROJECT_NAME=alu8, tag RUN
#   RUN_TAG=CHIP ./signoff.sh   # sign off the 4 mm chip run instead
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

# MEASURED paths. Do not drop the tech/ level.
DRC_DECK="${DRC_DECK:-$KLAYOUT_PATH/tech/drc/drc.lydrc}"
LVS_DECK="${LVS_DECK:-$KLAYOUT_PATH/tech/lvs/lvs.lylvs}"

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
[ -r "$DRC_DECK" ] || { echo "DRC deck not found: $DRC_DECK" >&2; exit 1; }
[ -r "$LVS_DECK" ] || { echo "LVS deck not found: $LVS_DECK" >&2; exit 1; }

# A KLayout report records the deck it ran under <generator>. If that path is not
# the PDK you built against, DRC silently checked a different process. There are
# two PDK copies on this machine -- confirmed byte-identical, but check anyway.
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
say "3. deck inspection -- what the decks actually reference"
for deck in "$DRC_DECK" "$LVS_DECK"; do
    echo "  $deck references:"
    grep -oE '\$[A-Za-z_][A-Za-z0-9_]*' "$deck" | sort -u | sed 's/^/    /'
done

# -----------------------------------------------------------------------------
say "4. DRC"
# The deck writes ./scl_drc.txt into the CURRENT directory. Run it from a scratch
# dir so it cannot overwrite the PDK's copy or a previous design's report, then
# move the result into place.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

klayout -b -zz \
    -rd input="$OUT/${DESIGN_TOP_CELL_NAME}.gds" \
    -rd top_cell="$DESIGN_TOP_CELL_NAME" \
    -r "$DRC_DECK" || echo "  (deck returned non-zero -- read the output above)"

if [ -s "$WORK/scl_drc.txt" ]; then
    mv "$WORK/scl_drc.txt" "$OUT/scl_drc.txt"
    # The report is XML; each violation is one <item>. An empty <items/> section
    # means zero violations -- that is how standalone INVR00 was proven clean.
    n=$(grep -c '<item>' "$OUT/scl_drc.txt" || true)
    tc=$(grep -oP '(?<=<top-cell>)[^<]*' "$OUT/scl_drc.txt" || true)
    of=$(grep -oP '(?<=<original-file>)[^<]*' "$OUT/scl_drc.txt" || true)
    echo "  report top-cell : $tc"
    echo "  report input    : $of"
    printf '  DRC items       : %s\n' "$n"
    if [ "$n" -eq 0 ]; then echo "  DRC CLEAN"; else echo "  DRC NOT CLEAN"; fi
    echo "  -> $OUT/scl_drc.txt"
else
    echo "  NO REPORT PRODUCED."
    echo "  The deck most likely takes its input from the layout open in the GUI"
    echo "  rather than from -rd. Compare the variables listed in step 3 against"
    echo "  the -rd names used above, and adjust."
fi

# -----------------------------------------------------------------------------
if [ "${DRC_ONLY:-0}" = "1" ]; then
    say "LVS skipped (DRC_ONLY=1)"; exit 0
fi

say "5. LVS"
cd "$WORK"
klayout -b -zz \
    -rd input="$OUT/${DESIGN_TOP_CELL_NAME}.gds" \
    -rd schematic="$OUT/${DESIGN_TOP_CELL_NAME}.cdl" \
    -rd target_netlist="$OUT/${DESIGN_TOP_CELL_NAME}.lvsdb" \
    -r "$LVS_DECK" || echo "  (deck returned non-zero -- read the output above)"

if [ -s "$OUT/${DESIGN_TOP_CELL_NAME}.lvsdb" ]; then
    need "$OUT/${DESIGN_TOP_CELL_NAME}.lvsdb"
    echo "  LVS database written. The verdict lives INSIDE it, not in a text file:"
    echo "  open it in KLayout's Netlist Browser to read match/mismatch."
else
    echo "  no .lvsdb produced -- see the note under step 4"
fi

say "DONE"
echo "  artefacts in $OUT"
