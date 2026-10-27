# OpenLane + SCL CP8D PDK on WSL2 — complete setup guide

**Audience:** someone setting up a second, independent machine to run the `alu8` flow
(or any CP8D design) from scratch on **Windows + WSL2**.
**Reference machine:** the runs in this repo were done on **W0, RHEL 9 bare metal**,
OpenLane **v1.0.2**, image digest
`ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64`.
Pin the same image — a different OpenROAD build will not reproduce the numbers here.

> **PDK distribution note.** This guide tells you *how* to install the SCL 0.8 µm (CP8D)
> kit. It does **not** contain any PDK content, and **no PDK file may ever be committed
> to this repository** — not `.lib`, not `.lef`, not the tech/DRC/LVS decks, not cell
> GDS, not the kit zip, and not any run tree's `tmp/` directory (which silently carries
> ~14.5 MB of merged PDK per run). Obtain the kit from its original source.

---

## 0. Before you start — the five things that actually go wrong

Read these now; each one has already cost someone a day.

| # | Trap | Symptom |
|---|---|---|
| 1 | **WSL2 default RAM cap** | global placement dies with `child killed: kill signal` |
| 2 | **Project tree on `/mnt/c/`** | 10–30× slower, and Docker bind-mount permissions break |
| 3 | **`PDK_ROOT` collision** | `sclenv` refuses to load, or you silently check against the wrong PDK |
| 4 | **`run_openroad_script` with no path argument** | cryptic Tcl error; it *requires* the script path |
| 5 | **`-tag XYZ`** | every `3_src` script hardcodes `runs/RUN` and writes there anyway |

---

## 1. Windows side: install WSL2 and give it enough memory

### 1.1 Install

In an **Administrator** PowerShell:

```powershell
wsl --install -d Ubuntu-22.04
wsl --set-default-version 2
wsl --status            # confirm "Default Version: 2"
```

Reboot if prompted. Ubuntu 22.04 is the recommended distro — the OpenLane host-side
tooling (`make`, `docker`, Python 3.10) is well-tested there.

### 1.2 🔴 Raise the memory limit — this is step one, not an optimisation

**WSL2 defaults to 50 % of host RAM, and the Linux OOM killer inside WSL sends SIGKILL
to the biggest process when it is hit.** OpenROAD's global placer (`gpl.tcl`) is that
process. The failure looks like a tool bug but is not:

```
[NesterovSolve] Iter: 1 overflow: 0.864376 HPWL: 45020962
child killed: kill signal
```

Tcl prints **"child killed: kill signal" only for SIGKILL**. SIGTERM prints "software
termination signal"; Ctrl-C prints "interrupt signal". Nothing inside OpenROAD, OpenLane
or the PDK sends SIGKILL to itself — it always comes from outside the process.

Create `C:\Users\<you>\.wslconfig`:

```ini
[wsl2]
memory=12GB          # at least 8GB; 12-16GB if the host has 32GB
processors=6
swap=8GB
localhostForwarding=true
```

Then from PowerShell:

```powershell
wsl --shutdown
```

Verify inside WSL — `MemTotal` must reflect the new value:

```bash
free -h
nproc
```

**Never run two OpenLane flows concurrently on one WSL2 instance.** They do not
coordinate memory; the kernel resolves the contention by killing one of them.
If a run dies with the signature above, confirm it before changing anything else:

```bash
dmesg -T | grep -iE 'oom|killed process'
```

### 1.3 Docker

Two valid options:

**(a) Docker Desktop for Windows** — enable *Settings → Resources → WSL Integration*
for your Ubuntu distro. Memory is governed by `.wslconfig` above, not by Docker
Desktop's own slider (that slider is for the Hyper-V backend).

**(b) Docker Engine natively inside WSL** — avoids Docker Desktop entirely:

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg make git python3 python3-pip
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
sudo service docker start      # systemd may not be enabled by default in WSL
```

Close and reopen the WSL terminal (group membership is read at login), then:

```bash
docker run --rm hello-world
```

If you get `Cannot connect to the Docker daemon`, run `sudo service docker start` again —
without systemd, WSL does not auto-start it on boot. To enable systemd instead, add to
`/etc/wsl.conf` and `wsl --shutdown`:

```ini
[boot]
systemd=true
```

### 1.4 🔴 Work inside the Linux filesystem, never `/mnt/c/`

```bash
mkdir -p ~/eda && cd ~/eda          # correct
# NOT: cd /mnt/c/Users/you/eda      # wrong
```

`/mnt/c` is a 9P network mount. It is an order of magnitude slower for the many small
file operations OpenLane does, and Linux file modes do not survive it, which breaks
bind-mounted scripts inside the container. If you need to browse the tree from Windows,
go the other way: `\\wsl$\Ubuntu-22.04\home\<you>\eda` in File Explorer.

---

## 2. Install OpenLane v1.0.2

```bash
cd ~/eda
git clone https://github.com/The-OpenROAD-Project/OpenLane.git
cd OpenLane
git checkout v1.0.2
```

Pull the exact image used for every run in this repo:

```bash
export OPENLANE_IMAGE_NAME=ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64
docker pull $OPENLANE_IMAGE_NAME
```

**Do not run OpenLane's `make` PDK bootstrap.** The default target installs sky130/gf180
via `volare`. We are not using those — the SCL kit ships its own `open_pdks` tree and
`PDK_ROOT` must point at it. Installing the sky130 PDK is harmless but wastes several GB
and creates a second `PDK_ROOT` you can accidentally pick up.

Smoke-test the container only:

```bash
docker run --rm -it $OPENLANE_IMAGE_NAME bash -lc 'yosys -V; openroad -version'
```

---

## 3. Install the SCL CP8D PDK

Obtain `SCL_CP8D_PDK_v1` (0.8 µm, the kit this repo targets) from its original source and
unpack it inside the WSL filesystem. The repo owner has the kit; **do not** fetch it from
a public mirror and do not re-publish it.

```bash
mkdir -p ~/eda/pdk && cd ~/eda/pdk
unzip "SCL_0.8 um PDK.zip"       # produces SCL_CP8D_PDK_v1/
```

The directories that matter:

```
SCL_CP8D_PDK_v1/
├── digital_cp8d/
│   └── my_dtech_cp8d/
│       └── Open_Source_SCL_0.8micron_PDK_digital/
│           └── open_source_scl_cp8d/
│               └── open_pdks/          <-- this is PDK_ROOT
│                   └── scl_cp8d/
│                       └── libs.tech/klayout/   <-- KLAYOUT_PATH/tech/{drc,lvs}
└── PadFrame_cp8d/
    └── Padframe_database/              <-- pad frame GDS + its own DRC/LVS screenshots
```

### 3.1 The environment, and the one rule about it

The kit ships a launcher called `sclenv`. It sets, in effect:

```
MY_DTECH_DIR  = <kit>/digital_cp8d/my_dtech_cp8d
PDK_ROOT      = $MY_DTECH_DIR/Open_Source_SCL_0.8micron_PDK_digital/open_source_scl_cp8d/open_pdks
PDK           = scl_cp8d
KLAYOUT_PATH  = $PDK_ROOT/scl_cp8d/libs.tech/klayout
OPENLANE_PATH = <your OpenLane checkout>
PADFRAME      = <kit>/PadFrame_cp8d/Padframe_database
aliases: olmount (docker mount with the SCL PDK), scldesigns (cd to project_scl_cp8d)
```

🔴 **`sclenv` is a launcher, not a sourceable script.** It `exec`s a new bash with an
`--rcfile`. If you try to `source` it from a shell that already has variables set, you
get `$PDK_ROOT` expanding to `//` and nothing works. **Run `sclenv` first, then do
everything else in the shell it gives you.**

🔴 **`sclenv` refuses to load if `$CADENCE_ROOT` and `$DDIROOT` are set** — both the
Cadence environment and `sclenv` set `PDK_ROOT`, and the collision is silent and
destructive. Use a **dedicated terminal** for the OpenLane/SCL flow and never source
the Cadence environment into it. On a fresh WSL install you will not have Cadence, so
this bites later, not now — but it is the single most common way to end up checking a
design against the wrong PDK.

Paths differ per machine. Edit `sclenv`'s `MY_DTECH_DIR` and `OPENLANE_PATH` to match
your WSL layout before first use, then:

```bash
sclenv
echo "$PDK_ROOT"        # must print a real path, not //
ls "$PDK_ROOT/scl_cp8d/libs.tech/klayout/tech/drc/"
```

⚠️ **The KLayout deck paths carry a `tech/` level**: `$KLAYOUT_PATH/tech/drc/drc.lydrc`
and `$KLAYOUT_PATH/tech/lvs/lvs.lylvs`. `$KLAYOUT_PATH/drc/...` does not exist.

---

## 4. Install KLayout (signoff DRC/LVS) — host side, not in the container

The OpenLane image does **not** carry the SCL KLayout decks, and signoff is run outside
the flow.

```bash
sudo apt install -y klayout
klayout -v
```

On WSL you need a working X server to use the GUI. WSLg (Windows 11, or Windows 10 with a
recent WSL kernel) provides this with no configuration — just run `klayout`. On older
setups install VcXsrv/X410 and `export DISPLAY=$(ip route show default | awk '{print $3}'):0`.

Batch DRC, once the design has a GDS:

```bash
klayout -b -r "$KLAYOUT_PATH/tech/drc/drc.lydrc" -rd input=alu8.gds -rd topcell=alu8
```

🔴 **The DRC report path is CWD-relative and there is no override.** The deck writes
`./scl_drc.txt` into whatever directory you are standing in. Run it from inside the PDK
tree and you will **overwrite the PDK's own `scl_drc.txt`**. Two designs checked from the
same directory silently clobber each other. Always run DRC from a scratch directory and
move the report out.

🔴 **Before believing any KLayout report, read its header:** `<original-file>`,
`<top-cell>` and `<generator>`. All three can silently be wrong — a report can describe a
different GDS than you think, and `<generator>` tells you which PDK copy the deck came
from. Check `<generator>` against `$PDK_ROOT`; if they differ you have two PDK trees and
must prove they are identical before trusting the result.

---

## 5. Lay out the design tree

```bash
cd ~/eda/OpenLane/designs
mkdir -p project_scl_cp8d/alu8
```

The design directory needs:

```
alu8/
├── config.json              <-- from this repo: flow/config.json
├── pin_order.cfg            <-- flow/pin_order.cfg
├── 1_RTL/alu8.v             <-- rtl/alu8.sv, RENAMED to .v  (see 5.1)
├── 3_src/*.tcl              <-- flow/3_src/  (11 files)
└── run_all.tcl              <-- flow/run_all.tcl, at the DESIGN ROOT, not in 3_src/
```

Everything in that list is in this repository under `flow/` and `rtl/`.

### 5.1 The seven input-side edits, and why they exist

These are the only things that differ from SCL's stock `cnt8` reference flow. Eight of
the ten stock `3_src` scripts are byte-identical to SCL's; only two differ, and they are
exactly the two any real design must touch.

1. **`1_RTL/alu8.v` — the SystemVerilog file renamed to `.v`.** `yosys_script.tcl`
   hardcodes `$::env(DESIGN_NAME).v`. ⚠️ The extension lies about the content.
2. **`3_src/yosys_script.tcl` line 2** — `-sv` added to `read_verilog`.
3. **`config.json`** — `DESIGN_NAME` and `DESIGN_TOP_CELL_NAME` both `alu8` (no `_top`
   split, unlike cnt8), `DIE_AREA "0 0 1000 1000"`, `CORE_AREA "100 100 900 900"`,
   **`CLOCK_PORT ""`**, **`CLOCK_NET ""`**, **`RUN_CTS false`**, `CLOCK_PERIOD 100`
   (a placeholder), `PLACE_SITE_HEIGHT 32.35`.
4. **`pin_order.cfg`** — 29 pins, N/S/W/E grouped.
5. **`3_src/run_sta.tcl`** — virtual clock replacing `[get_ports clk]` (see 5.2).
6. **`3_src/fill_cp8d.tcl`** — hand-written CTS substitute (see 5.3). SCL's README
   mandates this step but the kit never ships the file.
7. **`5_klayout/cdl_gds_script.source`** — three lines changed from the template
   (`smoke`/`cnt8`/`cnt8_top` → `alu8`/`alu8`/`alu8`).

### 5.2 Combinational design = no clock port

`run_sta.tcl` as shipped does `create_clock ... [get_ports clk]`, which **errors** when
there is no `clk` port. Replace with a virtual clock and zero I/O delays:

```tcl
create_clock -name vclk -period $::env(CLOCK_PERIOD)
set_input_delay  0.0 -clock vclk [all_inputs]
set_output_delay 0.0 -clock vclk [all_outputs]
```

OpenSTA then reports pure input-to-output combinational delay against the window.

🔴 **Never run `cts_cp8d.tcl`** on a combinational design — same `[get_ports clk]` problem.

### 5.3 🔴 The filler trap

`routing_cp8d.tcl` carries an SCL comment saying a combinational design can read the
**placement** DEF and skip CTS entirely. **Following that advice loses your filler cells.**

- `placement_cp8d.tcl` ends at `detailed_placement` + `check_placement`. It has **no**
  `filler_placement`.
- `cts_cp8d.tcl` is the **only** stock script that calls `filler_placement`.

CP8D ships **no tap/welltap cell** — at 0.8 µm the well and substrate contacts are drawn
inside every standard cell and inside the fillers. **Filler insertion *is* the tap
strategy on this process.** No fillers ⇒ broken nwell/implant continuity ⇒ signoff DRC
failures. `fill_cp8d.tcl` runs in place of `cts_cp8d.tcl` and writes to the same
`results/cts/` paths, so `routing_cp8d.tcl` needs no edit at all.

### 5.4 Things in `config.json` that are read and then ignored

`run_openroad_script` calls the `3_src` scripts **directly**, bypassing OpenLane's native
flow steps. Several variables are only consumed by those native steps, so on this flow
they are parsed into the environment and **never used**:

- `FP_PIN_ORDER_CFG` — there is no `place_pins` call in `floorplan_cp8d.tcl`. The only
  one is in `routing_cp8d.tcl`, unconstrained, *after* placement.
- `GPL_CELL_PADDING` / `DPL_CELL_PADDING` — `placement_cp8d.tcl` never calls
  `set_placement_padding`. To actually apply padding you must add the call yourself,
  before `global_placement`, in **site widths** (1 site = 3.9 µm), not µm.
- `DRC_EXCLUDE_CELL_LIST` / `..._OPT` — belong to the native Magic/KLayout steps.

⚠️ **This is why a run through OpenLane's native `./flow.tcl` steps is NOT comparable
stage-for-stage with a run through `3_src`,** even on identical RTL. Agree on which flow
is the reference before diffing two machines' results.

### 5.5 The floorplan destroys every odd row — do not "fix" it

`floorplan_cp8d.tcl` deletes alternating rows:

```tcl
foreach row $block { if {[expr $count % 2] != 0} { odb::dbRow_destroy $row }; incr count }
```

The tech LEF declares a SITE height of **25.35** while the cells are **32.35** tall, so
`initialize_floorplan -site CORE` builds overlapping rows. 25.35 × 2 = **50.70 µm**, which
is exactly the observed row pitch. 18.35 µm of every row is dead space (36 % wasted), which
is harmless at ~1 % utilisation but means no density number from this flow is meaningful.
**`PLACE_SITE_HEIGHT 32.35` is correct — never change it to 25.35.** Un-flipped rows at
25.35 pitch would lay one row's VDD rail across the next row's GROUND rail: a short.

---

## 6. Run the flow

```bash
sclenv                       # first, in a clean terminal
olmount                      # enters the container with the SCL PDK bind-mounted
# inside the container:
cd /openlane
./flow.tcl -design project_scl_cp8d/alu8 -tag RUN -interactive
```

You now get a **`%` Tcl prompt — not bash.** Then either source the scripted flow:

```tcl
source /openlane/designs/project_scl_cp8d/alu8/run_all.tcl
```

…or run the stages by hand:

```tcl
run_yosys_script      $::env(DESIGN_DIR)/3_src/yosys_script.tcl
run_openroad_script   $::env(DESIGN_DIR)/3_src/floorplan_cp8d.tcl
run_openroad_script   $::env(DESIGN_DIR)/3_src/pdn_cp8d.tcl
run_openroad_script   $::env(DESIGN_DIR)/3_src/placement_cp8d.tcl
run_openroad_script   $::env(DESIGN_DIR)/3_src/fill_cp8d.tcl
run_openroad_script   $::env(DESIGN_DIR)/3_src/routing_cp8d.tcl
run_openroad_script   $::env(DESIGN_DIR)/3_src/rcx_cp8d.tcl
run_openroad_script   $::env(DESIGN_DIR)/3_src/run_sta.tcl
```

🔴 **`run_openroad_script` and `run_yosys_script` take a PATH argument.** A bare call fails.

🔴 **`run_openroad_script` prints nothing on success.** Check `results/`, not the terminal.
A stage that "looked fine" and produced a 0-byte artefact has already caused one wrong
root-cause investigation here. **Check file sizes, not existence.**

🔴 **`-tag XYZ` is a trap.** Every `3_src` script hardcodes `runs/RUN` in its output paths.
`-tag CHIP` creates `runs/CHIP` for OpenLane's bookkeeping, and every stage then writes
into `runs/RUN` anyway, silently overwriting whatever is there. To do a second
configuration safely: `mv runs/RUN runs/RUN_<name>` first, swap `config.json`, run as
`-tag RUN`, then rename the result afterwards.

⚠️ **`-overwrite` deletes all of `runs/RUN`,** including any `.bak` subdirectories. Copy
`results/`, `cmds.log` and `5_klayout/` outside `runs/` before any re-run.

### 6.1 What a good run produces

| stage | artefact | 1 mm run size |
|---|---|---|
| yosys | `results/synthesis/alu8_sys.v` | 20,959 B — 210 CP8D cells |
| floorplan | `results/floorplan/alu8_fp.def` | 27,616 B (4 mm run) |
| pdn | | `SPECIALNETS 2`, metal1 7 µm followpins |
| placement | `results/placement/alu8_pl.def` | 404,259 B (4 mm run) |
| fill | `results/cts/alu8_plcts.def` | 566 components = 210 logic + 356 FILLER |
| routing | `results/routing/alu8_rt.def` | 319,149 B |
| | `results/routing/drc.rpt` | **0 bytes = router DRC pass** |
| rcx | `results/spef/alu8.spef` | 155,176 B |
| sta | `results/sta/timing_report.txt` | setup 11.61 ns, slack +88.39 MET |

Note `drc.rpt` is the one artefact where **0 bytes means success** — do not assert on its
size being non-zero.

⚠️ STA writes to `results/sta/`, **not** `reports/`. `runs/RUN/reports/` and `logs/` stay
empty forever on this flow, because raw `run_openroad_script` calls bypass OpenLane's
native reporting tree. That is expected, not a failure.

---

## 7. Interpreting results — the three caveats that must travel with every number

1. 🔴 **"≈86 MHz" is cell delay only.** The SCL PDK's RCX rule deck has no resistance
   model and CP8D has no capacitance model, so the SPEF is connectivity-only with every
   `*D_NET` capacitance = 0. This is **measured**, not assumed: the timing report is
   byte-identical across a 1 mm die and a 4 mm die (16× area, ~40× wire length) and across
   three placement densities. Never present it as post-layout signoff timing.
2. **Typical corner only** — 5 V / 25 °C. CP8D ships no worst-case library.
3. 🔴 **Router DRC ≠ signoff DRC.** `drc.rpt` 0 bytes means the router's own check passed
   against the **LEF abstract**, which contains no poly. Signoff flattens the real GDS.
   On this design, router DRC was clean while KLayout signoff found real violations.
   **Never write "DRC clean" without the word *router* unless KLayout says so.**

A known, reproduced example of (3): at low placement density, nets run long distances
*across* cells and vias land over poly the router cannot see — 6–8 `9.4.1` via-to-poly
violations with a clean `drc.rpt`. Both statements are true; they are about different views.

⚠️ **A KLayout item count is not a defect count.** An 8-item report on this design was
5 real vias — three were flagged twice, once per edge of the same via, separated by exactly
the via width. Parse the edge-pairs before quoting a number.

---

## 8. Verification checklist for a fresh WSL install

Run these in order; each must pass before the next is meaningful.

```bash
# Windows side
wsl --status                      # Default Version: 2
# WSL side
free -h                           # MemTotal reflects .wslconfig
nproc
docker run --rm hello-world
docker images | grep openlane     # the ff5509f6 tag is present
sclenv                            # new shell; no PDK_ROOT collision warning
echo "$PDK_ROOT"                  # a real path, not //
ls "$KLAYOUT_PATH/tech/drc/drc.lydrc"
klayout -v
pwd                               # under /home/..., NOT /mnt/c
```

Then the end-to-end check: run the flow and confirm
`runs/RUN/results/routing/alu8_rt.def` is **319,149 bytes** and
`runs/RUN/results/routing/drc.rpt` is **0 bytes**. The flow is deterministic — a re-run
with identical inputs reproduces these byte-for-byte, through signoff. If your sizes
differ, an input differs; find it before interpreting any result.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `child killed: kill signal` in `gpl.tcl` | SIGKILL from outside — OOM killer or WSL2 memory cap | §1.2; `dmesg -T \| grep -i oom`; raise `.wslconfig` memory; never run two flows at once |
| `Cannot connect to the Docker daemon` | no systemd in WSL | `sudo service docker start`, or enable systemd in `/etc/wsl.conf` |
| `sclenv` prints a `PDK_ROOT` collision warning | Cadence environment loaded in the same shell | use a dedicated terminal; never source `cadence.bash` here |
| `$PDK_ROOT` expands to `//` | you `source`d `sclenv` instead of running it | run `sclenv` as a command |
| `[get_ports clk]` error in STA or CTS | combinational design, no clock port | §5.2; and never run `cts_cp8d.tcl` |
| Signoff DRC fails on well/implant continuity | fillers missing | §5.3 — run `fill_cp8d.tcl` instead of CTS |
| A stage "succeeded" but the next one fails | `run_openroad_script` prints nothing on success and a dead stage can leave a 0-byte file | check artefact **sizes** after every stage |
| `runs/XYZ` is empty after `-tag XYZ` | scripts hardcode `runs/RUN` | §6, rename-first procedure |
| KLayout report shows the wrong design | report header lies, or CWD-relative output clobbered | read `<original-file>` / `<top-cell>` / `<generator>` before reading counts |
| `FOREIGN name SPAD00 differs from MACRO ASPAD00` | known SCL bug in `pads_cp8d.lef` | benign, ignore |
| LVS banner says "SCL C1D runset" while running CP8D | stale header text copied from the 1.2 µm kit | benign — it is the right deck |
| Everything is glacially slow | tree on `/mnt/c/` | §1.4, move to `~/` |

---

## 10. What **not** to commit

Before any `git add`, confirm none of these are staged:

- `*.lib`, `*.lef` (`tech_cp8d.lef`, `core_cp8d.lef`, `pads_cp8d.lef`, `corner_cp8d.lef`)
- `*.lydrc`, `*.lylvs`, `*.tech`, any cell GDS, `core_iolib_cp8d.cdl`
- the PDK zip or any part of the kit tree
- **`runs/*/tmp/`** — carries `merged.*.lef` and several `*.lib` ≈ 14.5 MB of PDK per run

⚠️ `rsync --exclude='*.bak'` matches the **directory** `RUN.bak/` too, silently skipping
your failure-evidence tree. Use explicit paths:
`--exclude='results/routing.bak/' --exclude='run_sta.tcl.bak'`.

Flow scripts, `config.json`, `pin_order.cfg` and all run outputs (netlist, DEFs, SPEF,
SDF, STA reports, `drc.rpt`) are fine — they describe our design and our flow. Cell
*names* appearing in a netlist are not PDK data.

---

## 11. Process note

CP8D is **0.8 µm = 800 nm**, a ~1990s node. It is an educational/open kit with **two metal
layers**, which is why vertical metal2 power stripes stay commented out in `pdn_cp8d.tcl`:
power and signal compete for the same tracks. In a 6–10 metal process you strap on upper
layers and never notice. That tradeoff is one of the more interesting things to be able to
explain about a CP8D project.

---

*Companion documents in this repo:* `docs/flow-notes.md` (the combinational-on-CP8D
technique in full), `docs/engineering-notes.md` (status, open items, corrections),
`docs/signoff.md` (KLayout DRC/LVS), `docs/determinism.md` (re-run evidence),
`docs/failed-runs.md` (how to read the error logs in `runs/`).
