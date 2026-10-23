#!/usr/bin/env python3
"""
def2gds.py -- Generic DEF -> GDS converter for KLayout batch mode.

This is a KLayout *batch* script -- it must be run with the `klayout`
executable itself (it uses the `pya` module, which only exists inside
KLayout), not with plain python3.

--------------------------------------------------------------------------
USAGE
--------------------------------------------------------------------------
All inputs are passed on the command line with `-rd name=value`. Inside
KLayout, each `-rd` entry becomes a global Python variable with that name,
which is how this script picks up its parameters -- nothing is hardcoded.

Only `in_def` is mandatory. Everything else falls back to defaults built
from your PDK_ROOT / PDK environment variables (matching the paths you
listed for the digital_cp8d library), so you can override only what you
need to change.

Minimal call (uses all defaults, only DEF given):

    klayout -b -zz \
        -rd in_def=./results/inverter_1_rt.def \
        -r def2gds.py

Fully explicit call (every path given on the command line):

    klayout -b -zz \
        -rd in_def=./results/inverter_1_rt.def \
        -rd out_gds=./results/inverter_1_rt.gds \
        -rd tech_lef="$PDK_ROOT/$PDK/libs.tech/openlane/digital_cp8d/lef/tech_cp8d.lef" \
        -rd cell_lefs="$PDK_ROOT/$PDK/libs.ref/digital_cp8d/lef/core_cp8d.lef,$PDK_ROOT/$PDK/libs.ref/digital_cp8d/lef/core_cp8d.lef,$PDK_ROOT/$PDK/libs.ref/digital_cp8d/lef/pads_cp8d.lef" \
        -rd in_gds="$PDK_ROOT/$PDK/libs.ref/digital_cp8d/gds/std_cells_cp8d.gds,$PDK_ROOT/$PDK/libs.ref/digital_cp8d/gds/pads_cp8d.gds" \
        -rd layer_map="$PDK_ROOT/$PDK/libs.tech/klayout/tech/scl_cp8d.map" \
        -rd dbu=0.001 \
        -r def2gds.py

Flags used above:
    -b    batch mode  (no GUI event loop)
    -zz   run fully headless, exit when the script finishes
    -rd   define a variable made available to the script
    -r    run this Python script

Any of these -rd variables accept a comma- (or semicolon-) separated list
where more than one file is needed (cell_lefs, in_gds).
--------------------------------------------------------------------------
"""

import os
import sys

import pya


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def split_list(value):
    """Turn a comma/semicolon/space separated -rd string into a clean list."""
    if not value:
        return []
    for sep in (",", ";"):
        value = value.replace(sep, " ")
    return [v.strip() for v in value.split() if v.strip()]


def get_var(name, default=""):
    """Fetch a -rd variable if it was supplied on the klayout command line."""
    return globals().get(name, default)


def die(msg):
    sys.stderr.write("ERROR: " + msg + "\n")
    sys.exit(1)


def check_files_exist(paths, label):
    missing = [p for p in paths if p and not os.path.isfile(p)]
    if missing:
        die(f"{label} not found:\n  " + "\n  ".join(missing))


# ---------------------------------------------------------------------------
# 1. Gather parameters (all overridable via -rd on the command line)
# ---------------------------------------------------------------------------

PDK_ROOT = os.environ.get("PDK_ROOT", "")
PDK = os.environ.get("PDK", "")
LIB = "digital_cp8d"

in_def = get_var("in_def", "")
if not in_def:
    die("you must pass -rd in_def=<path/to/design.def>")
if not os.path.isfile(in_def):
    die(f"DEF file not found: {in_def}")

default_tech_lef = f"{PDK_ROOT}/{PDK}/libs.tech/openlane/{LIB}/lef/tech_cp8d.lef"
default_cell_lefs = ",".join([
    f"{PDK_ROOT}/{PDK}/libs.ref/{LIB}/lef/core_cp8d.lef",
    f"{PDK_ROOT}/{PDK}/libs.ref/{LIB}/lef/corner_cp8d.lef",
    f"{PDK_ROOT}/{PDK}/libs.ref/{LIB}/lef/pads_cp8d.lef",
])
default_in_gds = ",".join([
    f"{PDK_ROOT}/{PDK}/libs.ref/{LIB}/gds/std_cells_cp8d.gds",
    f"{PDK_ROOT}/{PDK}/libs.ref/{LIB}/gds/pads_cp8d.gds",
    f"{PDK_ROOT}/{PDK}/libs.ref/{LIB}/gds/CORNER.gds",
])
default_layer_map = f"{PDK_ROOT}/{PDK}/libs.tech/klayout/tech/scl_cp8d.map"
default_out_gds = os.path.splitext(in_def)[0] + ".gds"

tech_lef = get_var("tech_lef", default_tech_lef)
cell_lefs = split_list(get_var("cell_lefs", default_cell_lefs))
in_gds_list = split_list(get_var("in_gds", default_in_gds))
layer_map = get_var("layer_map", default_layer_map)
out_gds = get_var("out_gds", default_out_gds)
dbu_str = get_var("dbu", "")  # leave empty -> use KLayout's own default

# Sanity-check every input file up front so failures are easy to diagnose.
check_files_exist([in_def], "DEF file")
check_files_exist([tech_lef], "Technology LEF")
check_files_exist(cell_lefs, "Cell LEF file")
check_files_exist(in_gds_list, "Cell GDS file")
if layer_map and not os.path.isfile(layer_map):
    sys.stderr.write(
        f"WARNING: layer map file not found: {layer_map}\n"
        "         continuing without it (pattern-based layer mapping)\n"
    )
    layer_map = ""

out_dir = os.path.dirname(os.path.abspath(out_gds))
if out_dir and not os.path.isdir(out_dir):
    os.makedirs(out_dir)

print("=" * 70)
print("DEF -> GDS conversion")
print("=" * 70)
print(f"  DEF file      : {in_def}")
print(f"  Tech LEF      : {tech_lef}")
print(f"  Cell LEFs     : {cell_lefs}")
print(f"  Cell GDS libs : {in_gds_list}")
print(f"  Layer map     : {layer_map or '(none - pattern based)'}")
print(f"  Output GDS    : {out_gds}")
print("=" * 70)

# ---------------------------------------------------------------------------
# 2. Configure the LEF/DEF reader
# ---------------------------------------------------------------------------

config = pya.LEFDEFReaderConfiguration()

# We list every LEF file explicitly, so don't auto-pull LEFs sitting next
# to the DEF file (avoids surprises/duplicated MACRO errors).
config.read_lef_with_def = False
config.lef_files = [tech_lef] + cell_lefs

# macro_resolution_mode = 2  ->  never use the LEF abstract geometry, always
# substitute the real physical cell layout. That is exactly what we want:
# pull actual polygons from std_cells_cp8d.gds / pads_cp8d.gds for every std cell.
config.macro_resolution_mode = 2
config.macro_layout_files = in_gds_list

if layer_map:
    config.map_file = layer_map

if dbu_str:
    config.dbu = float(dbu_str)

# Optionally attach net/pin/instance names as user properties -- useful for
# debugging nets later in the KLayout GUI. Uncomment if you want them:
# config.net_property_name = "net"
# config.pin_property_name = "pin"
# config.instance_property_name = "inst"

options = pya.LoadLayoutOptions()
options.lefdef_config = config

# ---------------------------------------------------------------------------
# 3. Read the DEF (this pulls in the LEFs + macro GDS automatically) and
#    write the merged result out as a single GDS file.
# ---------------------------------------------------------------------------

layout = pya.Layout()
layout.read(in_def, options)

top_cells = layout.top_cells()
print(f"Top cell(s) after import: {[c.name for c in top_cells]}")

layout.write(out_gds)

print(f"Done. Wrote {out_gds}")
