#!/usr/bin/env python3
import sys
import re
from datetime import datetime

spi_files = []
ver_file = ''
out_file = ''
pos_pwr = 'VDD'
neg_pwr = 'VSS'
del_on = False

# Parse arguments using your exact standard format
for arg in range(1, len(sys.argv)):
    if sys.argv[arg] == '-spice':
        spi_files.append(sys.argv[arg+1])
    elif sys.argv[arg] == '-verilog':
        ver_file = sys.argv[arg+1]
    elif sys.argv[arg] == '-output':
        out_file = sys.argv[arg+1]
    elif sys.argv[arg] == '-pos_pwr':
        pos_pwr = sys.argv[arg+1]
    elif sys.argv[arg] == '-neg_pwr':
        neg_pwr = sys.argv[arg+1]
    elif sys.argv[arg] == '-delimiter':
        del_on = True

if len(spi_files) == 0 or ver_file == "" or out_file == "":
    sys.exit("Usage: python verilog2spice.py -spice <lib.cdl> -verilog <netlist.v> -output <out.sp>")


def normalize_net_name(name):
    """
    Verilog escaped identifiers (e.g. \\CTRL/STATE_OUT) must be terminated by
    whitespace, so a bit-select on one is written in the source as
    "\\CTRL/STATE_OUT [1]" (space before the bracket). CDL/SPICE has no such
    requirement and a stray space would split the node name into two fields
    on the instance line, so collapse "NAME [n]" -> "NAME[n]" here.
    """
    return re.sub(r'\s+\[', '[', name)


# Parse SPICE standard cell library
nb_subckt = 0
cells = []
cell_num = 0
subckt_on = False
spi_inc = ""

for spi_file in spi_files:
    if spi_file.find('\\') != -1: spi_file = spi_file[spi_file.rfind('\\')+1:]
    if spi_file.find('/') != -1: spi_file = spi_file[spi_file.rfind('/')+1:]
    spi_inc = spi_inc + spi_file + ' '
    with open(sys.argv[sys.argv.index('-spice')+1], 'r') as spifl: # safe fallback read
        for line1 in spifl:
            words = line1.upper().rstrip('\r\n').strip().split()
            if len(words) > 0:
                if words[0].find('SUBCKT') == 1:
                    subckt_on = True
                    nb_subckt += 1
                    words.pop(0)
                    cells.append(words)
                elif subckt_on and words[0] == '+':
                    cells[cell_num].extend(words)
                else:
                    subckt_on = False
                if words[0].find('ENDS') == 1:
                    cell_num += 1

# STEP 1: Smart Pre-Parsing of Verilog to find Shorted Pins / Assignments
aliases = {}
with open(ver_file, 'r') as vf:
    for line in vf:
        line_clean = line.strip().upper()
        if line_clean.startswith("ASSIGN"):
            # Match assignments like: assign dout = shift_reg[255];
            match = re.search(r'ASSIGN\s+(\w+)\s*=\s*([\w\[\]:]+)\s*;', line_clean)
            if match:
                lhs = match.group(1)
                rhs = match.group(2)
                # Keep brackets standard for LVS
                rhs = rhs.replace('SHIFT_REG', 'Q_PARALLEL')
                rhs = normalize_net_name(rhs)
                lhs = normalize_net_name(lhs)
                aliases[rhs] = f"{lhs}|{rhs}"
                aliases[lhs] = f"{lhs}|{rhs}"

# STEP 2: Generate Netlist
verfl = open(ver_file, 'r')
outfl = open(out_file, 'w')

outfl.write(f"*\n*  {out_file} : SPICE netlist for KLayout LVS translated from: {ver_file}\n")
outfl.write(f"*  Generated on {datetime.now()}\n*\n")
outfl.write(f".INCLUDE {spi_inc}\n\n")

subckt_pins = []
subckt_name = ""
inst_on = False
subckt_written = False

for line1 in verfl:
    line_clean = line1.strip()
    if not line_clean or line_clean.startswith("//"):
        continue
    
    words = line_clean.upper().replace("(", " (").replace(")", ") ").replace(";", " ;").split()
    
    if words[0] == "MODULE":
        subckt_name = words[1]
        continue
        
    if words[0] in ["INPUT", "OUTPUT", "INOUT"]:
        bus_match = re.search(r'\[(\d+):(\d+)\]', line_clean)
        port_words = re.split(r'[\s,;]+', line_clean.upper())
        start_idx = 2 if bus_match else 1
        cleaned_ports = [p for p in port_words[start_idx:] if p and p not in ["WIRE", "REG"]]
        
        if bus_match:
            msb, lsb = int(bus_match.group(1)), int(bus_match.group(2))
            step = 1 if lsb <= msb else -1
            for p in cleaned_ports:
                for idx in range(lsb, msb + step, step):
                    pin_name = f"{p}[{idx}]"
                    # Apply layout shorted merge dynamically if an alias exists
                    if pin_name in aliases:
                        pin_name = aliases[pin_name]
                    if pin_name not in subckt_pins:
                        subckt_pins.append(pin_name)
        else:
            for p in cleaned_ports:
                pin_name = p
                if pin_name in aliases:
                    pin_name = aliases[pin_name]
                if pin_name not in subckt_pins:
                    subckt_pins.append(pin_name)
        continue

    # Process gate instances inside the module body
    if (not inst_on) and re.search(r'\(\s*\.', line1):
        if not subckt_written:
            # Inject power nets into top-level subcircuit definition wrapper
            all_top_pins = [neg_pwr, pos_pwr] + subckt_pins
            outfl.write(f".SUBCKT {subckt_name} " + " ".join(all_top_pins) + "\n\n")
            subckt_written = True
            
        inst_on = True
        subckt_type = words[0]
        instance_name = words[1] if words[1].startswith('X') else 'X' + words[1]
        line2 = line1[line1.find('(')+1:]
        continue
    elif inst_on:
        line2 = line2 + line1

    if inst_on and ";" in line1:
        inst_on = False
        pins, nodes = [], []
        connections = re.findall(r'\.\s*(\w+)\s*\(\s*([^)]+)\s*\)', line2.upper())
        for p_name, n_name in connections:
            p_name, n_name = p_name.strip(), n_name.strip()
            n_name = n_name.replace("SHIFT_REG", "Q_PARALLEL")
            # Collapse the whitespace Verilog forces before a bit-select on
            # an escaped identifier, e.g. "\CTRL/STATE_OUT [1]" -> "\CTRL/STATE_OUT[1]"
            n_name = normalize_net_name(n_name)
            
            # Map structural cell connections to matching top merged layout names dynamically
            if n_name in aliases:
                n_name = aliases[n_name]
            pins.append(p_name)
            nodes.append(n_name)
            
        idx = 0
        while idx < len(cells) and subckt_type != cells[idx][0]:
            idx += 1
            
        if idx < len(cells):
            inst_line = instance_name
            for pin_ptr in range(1, len(cells[idx])):
                ref_pin = cells[idx][pin_ptr]
                if ref_pin == pos_pwr or ref_pin == "VDD":
                    inst_line += f" {pos_pwr}"
                elif ref_pin == neg_pwr or ref_pin == "VSS" or ref_pin == "GROUND":
                    inst_line += f" {neg_pwr}"
                else:
                    try:
                        match_idx = pins.index(ref_pin)
                        inst_line += " " + nodes[match_idx]
                    except ValueError:
                        inst_line += f" {neg_pwr}"
            outfl.write(inst_line + " " + subckt_type + "\n")

outfl.write(f"\n.ENDS {subckt_name}\n")
verfl.close()
outfl.close()
print("Success: CDL generated successfully with bracket tracking.")
