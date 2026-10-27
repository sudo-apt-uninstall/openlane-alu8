# OpenLane + SCL CP8D PDK on WSL2 — setup guide

**Written for Sai Darshan**, from your actual machine state (bash history read
2026-10-27) and the kit's own `Readme_0.8u_digital.txt`.

This follows SCL's procedure, whose section letters **(A)–(J)** are preserved so you can
read both side by side. 🪟 marks WSL-specific additions that are **not** in SCL's README.

---

## 🔴 Two corrections before anything else

### 1. Your ALU is not our ALU — and that is good news

Deepesh described your run as "same RTL". **It isn't.** From your history, `alu.v` is:

```verilog
module alu #(parameter W = 8) (
    input clk, input rst_n, input [W-1:0] a, b, input [2:0] op,
    output reg [W-1:0] y, output reg carry, output reg zero );
    always @(*)        ... // compute into r
    always @(posedge clk) ... // REGISTER y, carry, zero
```

Ours (`rtl/alu8.sv`) is `module alu8 (a, b, op, result, zero, carry)` — **purely
combinational, no clock, no reset, `always_comb` only.** The op encodings differ too:
your `101` is `~a` and `110`/`111` are shift-by-one; ours are shift-by-`b[2:0]` with no
NOT operation.

**Why this matters more than it sounds:**

| | your `alu` | our `alu8` |
|---|---|---|
| clock | **yes** — `clk`, `rst_n` | none |
| flops | **yes** — 8+ DFFs | none |
| `RUN_CTS` | **`true`** | `false` |
| `cts_cp8d.tcl` | **run it, normally** | errors — no `clk` port |
| `filler_placement.tcl` workaround | **not needed** | required |
| timing path | clk→Q + logic + setup | pure in→out delay |
| our 210-cell / 11.61 ns numbers | **do not apply** | apply |

🔴 **So ignore every "combinational workaround" you may have heard about from our run.**
You are on the kit's *mainline* path — the one SCL built the flow around and proved with
`cnt8`, which is also a clocked design. It works unmodified. We are the awkward case,
not you.

🔴 **And your results can never be byte-compared to ours.** Different RTL, different
netlist, different everything downstream. If you want a direct comparison, one of you has
to run the other's RTL.

### 2. Your crash is not confirmed as OOM yet

Your history shows you already checked, twice:

```bash
dmesg 2>/dev/null | grep -i -E "killed process|out of memory" | tail -5
sudo dmesg | grep -i -E "killed process|out of memory|oom" | tail -5
```

If those came back **empty**, the OOM theory is unproven. See §0.2 — I have listed the
alternatives and how to tell them apart. **Also:** your history contains

```
wsl.exe --shutdownn
```

— **a typo** (`--shutdownn`, double n). That command failed, so WSL was never restarted,
so **no memory setting you may have changed has ever taken effect.** Start there.

---

## 🪟 0. Your current setup, and what to do with it

### 0.1 Where you are now

| what you have | status |
|---|---|
| **Ubuntu 24.04** in WSL2 | ⚠️ SCL tested on **22.04.5** — see below |
| `~/OpenLane` from `mukulkumar011/EDA-Tools-Installer` | **deleted** by you, correctly — it had no `flow.tcl` |
| `~/OpenLaneRepo` — real `The-OpenROAD-Project/OpenLane` clone | ✅ this is your OpenLane |
| `~/scl_pdk/` — unzipped kit | ✅ |
| `~/pdks/scl_cp8d` — `scl_cp8d` copied out of the kit | ✅ works, see 0.4 |
| image `openlane:ff5509f6…-amd64` | ✅ correct, matches ours |
| `designs/alu/config.json` — hand-written, native flow | 🔴 replace, see §C |
| runs 1–8, hand-tuned `FP_PDN_*` | 🔴 the rabbit hole, see 0.5 |

**Ubuntu 24.04 vs 22.04.5.** SCL's README is explicit: *"choosing Ubuntu 22.04 LTS will
give you the most out-of-the-box, error-free experience."* Everything real runs inside the
OpenLane container, so the distro mostly doesn't matter — **except for KLayout**, which
runs on the host and does the signoff. Do not reinstall yet; just be aware that if KLayout
misbehaves, 24.04 is a suspect. A second distro side by side is cheap:
`wsl --install -d Ubuntu-22.04`.

### 0.2 🔴 The crash — diagnose before you change anything

```
[INFO GPL-0028] BinCnt: 16 16
[NesterovSolve] Iter: 1 overflow: 0.864376 HPWL: 45020962
child killed: kill signal
```

**"child killed: kill signal" is Tcl's rendering of SIGKILL.** SIGTERM → "software
termination signal"; Ctrl-C → "interrupt signal". Nothing in OpenROAD, OpenLane or the PDK
sends SIGKILL to itself; it always comes from outside. The placer was *healthy* — bins
built (16×16 = 256 vs IdealBinCnt 331), iteration 1 at a normal overflow of 0.864. It did
not fail. It was killed.

Four candidates, in order of likelihood:

**(a) WSL2 memory ceiling / OOM killer.** Default is 50 % of host RAM.
Fix — create `C:\Users\jacks\.wslconfig`:

```ini
[wsl2]
memory=12GB          # at least 8GB; 12-16GB if the host has 32GB
processors=6
swap=8GB
```

then, **spelled correctly**:

```powershell
wsl --shutdown
```

Verify it took effect — this is the step that was skipped:

```bash
free -h          # MemTotal must now show ~12GB
```

**(b) Two flows at once.** You have eight run trees and were iterating fast. Two
concurrent OpenROAD placements do not coordinate memory; the kernel resolves it by killing
one. Serialise.

**(c) Docker Desktop / `vmmem` pressure from the Windows side.** If `dmesg` is empty but
`free -h` showed memory nearly exhausted during the run, this is it. You already had the
right instrument running:

```bash
watch -n 1 'free -m | head -2; docker stats --no-stream --format "{{.MemUsage}}"'
```

Leave that in a second terminal through the whole placement and **watch whether it climbs
to the ceiling before the kill**. If it dies with gigabytes free, memory is not the cause.

**(d) Timing-driven placement.** You set `GPL_TIMING_DRIVEN: 0` and
`GPL_ROUTABILITY_DRIVEN: 0` for run7 — good instinct, those invoke the resizer and repeated
STA and are the memory-hungry part. **Keep them off while debugging.** Note it still died
with them off, which weakens the pure-memory theory and strengthens (a)/(c).

🔴 **SCL's README Note 2 — "If placement, routing fails user need to rerun script after
changing the value of density and area in config.json" — does NOT apply to a SIGKILL.** It
is for a placer that legitimately cannot fit the design. You have already spent runs 5–8
sweeping die area 1500→1800 and density 0.4→0.5→0.6 on that advice. **Stop sweeping.** A
killed process tells you nothing about density.

⚠️ The two trailing `[WARNING]` lines about `scl_cp8d` / `digital_cp8d` instantiated
stdcells are a **red herring**. OpenLane always appends "the failure may have been because
of the following warnings" with whatever it collected; that one is emitted at synthesis and
the flow reached Step 6. Do not disable `QUIT_ON_LINTER_ERRORS` over it.

### 0.3 🔴 Move off `/mnt/c`

You unzipped from `/mnt/c/Users/jacks/Downloads` — fine for a one-off copy, which is what
you did. Just never *work* there. `/mnt/c` is a 9P network mount: an order of magnitude
slower for OpenLane's many small file operations, and Linux file modes don't survive it,
which breaks bind-mounted scripts inside the container. Your trees are already under `~/`.
Keep it that way.

### 0.4 Your PDK path works — here's why, and the gotcha you dodged

You did:

```bash
cp -r ~/scl_pdk/SCL_CP8D_PDK_v1/digital_cp8d/my_dtech_cp8d/my_dtech_cp8d/.../open_pdks/scl_cp8d ~/pdks/
```

and run with `-e PDK_ROOT=$HOME/pdks`. That satisfies OpenLane's
`$PDK_ROOT/$PDK/libs.tech/openlane/config.tcl` convention. ✅ Correct.

⚠️ Note the **doubled `my_dtech_cp8d/my_dtech_cp8d`** in that path — a side effect of your
recursive unzip loop, which extracted `my_dtech_cp8d.zip` into a directory of the same
name. Harmless, but it means your path will not match SCL's documentation or anything in
this repo. Write it down.

⚠️ Your earlier symlink attempts (`ln -s .../scl080 .../scl_cp8d`, then hand-building
`libs.tech/openlane/digital_cp8d/lef/` link by link) are the thing the `cp -r` replaced.
**Don't go back to symlinks** — the flow reads many files from that tree and a half-linked
PDK fails in a different place each time, which is exactly the loop you were in.

SCL's own method is simpler: move `my_dtech_cp8d` to `~/` and let
`cp8d_pdk_env_setting.source` compute `PDK_ROOT` for you (§B). Either works. If you keep
yours, you must pass `PDK_ROOT` explicitly on every `docker run`, which you already do.

### 0.5 🔴 Stop hand-configuring the PDN — two reasons

Runs 2–4 were spent on `FP_PDN_VERTICAL_LAYER`, `FP_PDN_VPITCH`, `FP_PDN_RAIL_WIDTH` and
friends. Your arithmetic was good — `FP_PDN_HPITCH: 97.05` is exactly **3 × 32.35 µm**,
i.e. three cell rows, and `FP_PDN_HOFFSET: 16.2` is half a row. That is the right way to
think about it.

**But:**

🔴 **`"FP_PDN_VERTICAL_LAYER": "metal2"` puts power straps on the only vertical signal
layer this process has.** CP8D is a **2-metal** process. `routing_cp8d.tcl` pins signals to
`metal1-metal2`. Vertical metal2 power straps consume the vertical routing resource
outright. SCL knows this: in their own `pdn_cp8d.tcl`, **every `add_pdn_stripe -layer
metal2` line is commented out.** Power enters at a metal1/metal2 ring and runs inward along
metal1 followpins (width 7.0) per row, fed from both ends. In a 6–10 metal process you
strap on upper layers and never notice; at 2 metals power and signal fight for the same
tracks.

🔴 **And you don't need to configure any of it.** `3_src/pdn_cp8d.tcl` is a finished,
silicon-proven PDN script. Moving to the kit flow (§E) deletes this entire problem — there
are no `FP_PDN_*` variables to tune, because the script does the work.

### 0.6 🔴 One real hazard in the native flow: overlapping rows

The CP8D tech LEF declares a SITE height of **25.35** while the cells are **32.35** tall.
SCL's `floorplan_cp8d.tcl` works around this by destroying every second row:

```tcl
foreach row $block { if {[expr $count % 2] != 0} { odb::dbRow_destroy $row }; incr count }
```

giving a 50.70 µm pitch. **OpenLane's native floorplan does not do this.** On the native
path your rows are 25.35 apart while your cells are 32.35 tall, so **rows overlap by
7 µm** — and an un-flipped row's VDD rail (y 17.700–28.850) lands across the next row's
GROUND rail (21.850–32.200). That is a **short**, and it is the kind of thing router DRC
will not tell you about.

This alone is sufficient reason to move to `3_src`. It will not cause a SIGKILL, but a run
that completes on the native path is not necessarily a run you can believe.

### 0.7 🪟 Install KLayout 0.30.5

SCL tested **0.30.5**. `apt install klayout` on Ubuntu 24.04 ships older. Get the Ubuntu
`.deb` from <https://www.klayout.de/build.html>:

```bash
sudo apt install -y ./klayout_0.30.5-1_amd64.deb
klayout -v
```

You already ran `klayout .../results/final/gds/alu.gds` successfully, so your X is working
(WSLg). The flow **requires** the GUI — SCL's DRC and LVS steps are menu-driven (§F).

---

## (A) PDK integration — the kit's way

If you want to align with SCL's documented layout rather than your `~/pdks` copy:

1. Move `my_dtech_cp8d` to `~/` (watch the doubled directory, §0.4).
2. Copy `project_scl_cp8d` into your OpenLane `designs/`:

```bash
cp -r ~/scl_pdk/SCL_CP8D_PDK_v1/digital_cp8d/my_dtech_cp8d/my_dtech_cp8d/Open_Source_SCL_0.8micron_PDK_digital/open_source_scl_cp8d/open_pdks/scl_cp8d/libs.ref/digital_cp8d/project_scl_cp8d ~/OpenLaneRepo/designs/
```

⚠️ **There is no `sclenv` and no `olmount` in this kit.** If you have seen those
mentioned, they are local aliases on Deepesh's machine. The kit ships
`cp8d_pdk_env_setting.source` and plain `make mount`.

---

## (B) Environment and project setup

`~/OpenLaneRepo/designs/project_scl_cp8d/cp8d_pdk_env_setting.source` **is sourceable**
and exports exactly six things:

```bash
export HOME=~
export OPENLANE_PATH="$HOME/OpenLane"                  # <-- EDIT: yours is OpenLaneRepo
export MY_DTECH_DIR_PATH=$HOME/my_dtech_cp8d           # <-- EDIT if elsewhere
export PDK_ROOT=$MY_DTECH_DIR_PATH/Open_Source_SCL_0.8micron_PDK_digital/open_source_scl_cp8d/open_pdks
export PDK=scl_cp8d
export KLAYOUT_PATH=$PDK_ROOT/$PDK/libs.tech/klayout
```

🔴 **You must edit `OPENLANE_PATH` to `$HOME/OpenLaneRepo`** — the default assumes
`~/OpenLane`, which you deleted. The variable is `MY_DTECH_DIR_PATH`, not `MY_DTECH_DIR`.

```bash
cd ~/OpenLaneRepo/designs/project_scl_cp8d
source cp8d_pdk_env_setting.source
```

It prints `HOME`, `MY_DTECH_DIR`, `PDK_ROOT`, `PDK`, `OPENLANE_PATH`. **Read them.**
🔴 **Re-source in every new terminal** — SCL says so twice, and it is the commonest reason
a step mysteriously stops working.

### Create your project

```bash
cd ~/OpenLaneRepo/designs/project_scl_cp8d
cp -r sample_project_files_cp8d alu
cd alu
cp ~/OpenLaneRepo/designs/alu/src/alu.v 1_RTL/alu.v     # your existing RTL
```

The shipped skeleton:

```
alu/
├── 1_RTL/                    <-- alu.v here. MUST be .v (yours already is)
├── 2_iverilog_prelayout/tb_prelay_sim/tb_prelay_script.source
├── 3_src/                    <-- TEN tcl scripts
├── 4A_synthesis_netlist/
├── 4B_synthesis_netlist_sim/tb_prelay_sim/tb_sys_sim_script.source
├── 5_klayout/{cdl_gds_script.source, lvs_drc/, script/{def2gds.py, verilog2spice.py}}
├── 6_iverilog_postlayout/tb_postlay_sim/tb_postlay_script.source
├── config.json
└── pin_order.cfg
```

**`3_src` ships exactly ten scripts:** `yosys_script.tcl`, `floorplan_cp8d.tcl`,
`pdn_cp8d.tcl`, `pdn_order.tcl`, `placement_cp8d.tcl`, `cts_cp8d.tcl`,
`routing_cp8d.tcl`, `rcx_cp8d.tcl`, `run_sta.tcl`, `script_openlane.tcl`.

✅ Your RTL is already plain Verilog with a `.v` extension, so unlike us you need **no**
`-sv` edit to `yosys_script.tcl` and no file rename.

---

## (C) Configuration — replace your hand-written `config.json`

Your native-flow config (`VERILOG_FILES`, `FP_SIZING`, `FP_CORE_UTIL`, `FP_PDN_*`) is for a
different flow. **The kit's `config.json` has a different shape** — the `3_src` scripts
read the RTL from `1_RTL/` by `DESIGN_NAME`, so there is no `VERILOG_FILES` key at all.

Shipped sample:

```json
{
    "DESIGN_NAME": "test",
    "DESIGN_TOP_CELL_NAME": "test_top",
    "DIE_AREA": "0 0 5000 5000",
    "CORE_AREA": "500 500 4500 4500",
    "CLOCK_PERIOD": 100,
    "CLOCK_PORT": "clk",
    "CLOCK_NET": "ref::$CLOCK_PORT",
    "RUN_CTS": true,
    "PL_TARGET_DENSITY": 0.45,
    "FP_PIN_ORDER_CFG": "dir::pin_order.cfg",
    "FP_PDN_SKIPTRIM": true
}
```

**For your `alu`, change only four fields:**

```json
{
    "DESIGN_NAME": "alu",
    "DESIGN_TOP_CELL_NAME": "alu",
    "DIE_AREA": "0 0 1000 1000",
    "CORE_AREA": "100 100 900 900",
    "CLOCK_PERIOD": 100,
    "CLOCK_PORT": "clk",
    "CLOCK_NET": "ref::$CLOCK_PORT",
    "RUN_CTS": true,
    "PL_TARGET_DENSITY": 0.45,
    "FP_PIN_ORDER_CFG": "dir::pin_order.cfg",
    "FP_PDN_SKIPTRIM": true,
    "PLACE_SITE": "CORE",
    "PLACE_SITE_WIDTH": 3.9,
    "PLACE_SITE_HEIGHT": 32.35
}
```

- ✅ **`CLOCK_PORT "clk"`, `CLOCK_NET`, `RUN_CTS true` all stay as shipped** — your design
  is clocked. This is the path the kit was built for.
- **`DESIGN_NAME` == `DESIGN_TOP_CELL_NAME` == `alu`** — your module is `alu`, with no
  separate `_top` wrapper. The sample splits them (`test`/`test_top`); yours doesn't.
- **`DIE_AREA` 1000 / `CORE_AREA` 100..900.** Start here, not at 1800. Your design is
  small. The sample's 5000 wastes an enormous amount of filler, and your 1500–1800 sweep
  was chasing a non-existent capacity problem.
- **`CLOCK_PERIOD` 100 is a placeholder** — see §E.2.
- **`PLACE_SITE_HEIGHT 32.35`** — never 25.35, see §0.6.
- **No `FP_PDN_*` keys.** `pdn_cp8d.tcl` handles it. Delete them.

Then edit `pin_order.cfg` for your 21 pins — `clk`, `rst_n`, `a[7:0]`, `b[7:0]`, `op[2:0]`,
`y[7:0]`, `carry`, `zero`. A reasonable grouping: `#N a[.*]` · `#S b[.*]` ·
`#W op[.*] clk rst_n` · `#E y[.*] zero carry`.

⚠️ **`FP_PIN_ORDER_CFG` has no effect on this flow.** `floorplan_cp8d.tcl` contains no
`place_pins` call; the only one is in `routing_cp8d.tcl`, unconstrained, *after* placement.
The variable is read and never used. Write the file anyway — it documents intent, and it
matters the moment you integrate a pad frame (§J).

---

## (D) RTL simulation — do this, we never did

```bash
cd ~/OpenLaneRepo/designs/project_scl_cp8d/alu/2_iverilog_prelayout/tb_prelay_sim
# write tb_alu.v here, then edit the four variables inside the .source file:
#   PROJECT_NAME, DESIGN_NAME, DESIGN_TOP_CELL_NAME, TESTBENCH_TOP_CELL_NAME
source tb_prelay_script.source
```

You have `iverilog` installed already. We never ran either simulation step on our design —
it is the single biggest gap in our run. If you complete §D and §G you will have something
we don't, and it is the only step that proves the netlist *computes correctly*.

---

## (E) OpenLane RTL-to-DEF flow

```bash
cd ~/OpenLaneRepo/designs/project_scl_cp8d
source cp8d_pdk_env_setting.source      # EVERY new terminal
cd ~/OpenLaneRepo
make mount PDK_ROOT=$MY_DTECH_DIR_PATH/Open_Source_SCL_0.8micron_PDK_digital/open_source_scl_cp8d/open_pdks PDK=scl_cp8d
```

If you prefer your raw `docker run` invocation, it works — just keep `-e PDK_ROOT=` and the
`$HOME` mount. `make mount` is simply the kit's documented form.

Inside the container:

```bash
cd /openlane
./flow.tcl -design project_scl_cp8d/alu -tag RUN -interactive
```

That gives a **`%` Tcl prompt — not bash.** Then:

```tcl
run_yosys_script    $::env(DESIGN_DIR)/3_src/yosys_script.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/floorplan_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/pdn_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/placement_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/cts_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/routing_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/rcx_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/run_sta.tcl
```

✅ **`cts_cp8d.tcl` is in your list and that is correct** — you have a clock. It also
performs `filler_placement`, which is why you don't need the missing-file workaround
below.

Or in one go — **and for you, unedited, this is safe**:

```tcl
source $::env(DESIGN_DIR)/3_src/script_openlane.tcl
```

That batch script runs exactly the eight lines above. ⚠️ It is only unusable for a
*combinational* design, because line 5 is `cts_cp8d.tcl`.

🔴 **`run_openroad_script` and `run_yosys_script` take a PATH argument.** A bare call fails.

🔴 **`run_openroad_script` prints nothing on success.** Check `results/`, not the terminal.
A dead stage can leave a **0-byte** artefact that looks present — this cost us a wrong
root-cause investigation. **Check sizes, not existence.**

⚠️ **`-tag XYZ` does not behave like it does on the native flow.** Every `3_src` script
hardcodes `runs/RUN` in its output paths, so `-tag run9` creates `runs/run9` for
bookkeeping while every stage writes into `runs/RUN` anyway, silently overwriting it. This
is a real change from your current habit of `-tag run1…run8`. For a second configuration:
`mv runs/RUN runs/RUN_<name>` first, swap `config.json`, run as `-tag RUN`, rename after.

⚠️ `-overwrite` deletes **all** of `runs/RUN`. SCL's README says to back up `runs/RUN` and
`4A_synthesis_netlist` first. Also copy `5_klayout/` out.

### E.1 The combinational trap — **does not apply to you**, but know it exists

SCL's README Note 1 says: *"If your design is a purely combinational circuit or a ring
oscillator, skip the `cts_cp8d.tcl` script and run `filler_placement.tcl` instead."*
**`filler_placement.tcl` is not in the kit** — `3_src` ships ten scripts and that is not
one of them. The mandatory step ships missing.

It matters because **CP8D has no tap/welltap cell**: at 0.8 µm the well and substrate
contacts are drawn inside every standard cell *and inside the fillers*, so **filler
insertion IS the tap strategy on this process**. Skip it and you get broken nwell/implant
continuity and signoff DRC failures.

You run `cts_cp8d.tcl`, which calls `filler_placement` itself. **So you are covered.**
Just confirm fillers landed:

```bash
grep -c FILLER runs/RUN/results/cts/alu_plcts.def
```

If you ever run our combinational `alu8`, use `flow/3_src/fill_cp8d.tcl` from this repo.

### E.2 `CLOCK_PERIOD` never reaches synthesis

`abc -liberty` is called with no `-D` and no SDC, so ABC maps for **area**, not timing.
`CLOCK_PERIOD` only feeds `create_clock` in `run_sta.tcl`. A full re-run to "get
timing-driven synthesis" buys nothing — **re-run `run_sta.tcl` alone** after changing it.

✅ `run_sta.tcl` works **unmodified** for you: it does
`create_clock -name CLK -period $::env(CLOCK_PERIOD) [get_ports clk]`, and you have a `clk`
port. (We had to replace that line with a virtual clock. You don't.)

Start at 100 ns, read the real path delay, then tighten. For reference, SCL's `cnt8` — also
clocked, 30 cells — closed at **7.93 ns ≈ 120 MHz**, with `DFFL11` clk→Q at 2.17–2.80 ns.
Your ALU has a wider combinational cone in front of the flops, so expect slower.
⚠️ **`NND600` alone costs 2.50 ns** — wide gates at 0.8 µm / 5 V are slow and will dominate
your critical path.

### E.3 Expected results

We cannot give you byte sizes — different RTL (§1). What to check instead:

1. **Synthesis cell count is sane.** Read
   `runs/RUN/results/synthesis/` and the stat report. Expect **8 `DFFL11`** flops (one per
   `y` bit) plus `carry`/`zero` registers, and gate-level adder logic rather than `ADR100`
   (area-mode mapping, see E.2).
2. **Rows.** Floorplan should report a **50.7 µm pitch**, not 25.35 — that is SCL's
   alternating-row deletion working as intended (§0.6).
3. **Fillers present** after CTS (§E.1).
4. **`runs/RUN/results/routing/drc.rpt` is 0 bytes** — the one artefact where empty means
   pass.
5. **STA** at `results/sta/`, **not** `reports/`.

⚠️ `runs/RUN/reports/` and `logs/` stay empty forever on this flow, because raw
`run_openroad_script` calls bypass OpenLane's native reporting tree. Expected, not a
failure — but it does mean the `grep … logs/placement/6-global.log` habit from your native
runs will no longer find anything. Read `results/` instead.

Then `exit` twice to leave the container.

---

## (F) DEF-to-GDS, DRC and LVS in KLayout

```bash
cd ~/OpenLaneRepo/designs/project_scl_cp8d/alu/5_klayout
# edit cdl_gds_script.source: PROJECT_NAME, DESIGN_NAME, DESIGN_TOP_CELL_NAME
source cdl_gds_script.source
```

For you those become your project folder name / `alu` / `alu`. The template ships pointing
at the `cnt8` sample — that edit is a genuine input you must recreate on a clean checkout.

The script runs `verilog2spice.py` → `alu.cdl`, `def2gds.py` → `alu.gds`, then opens
KLayout. Output lands in `5_klayout/lvs_drc/`.

⚠️ **It builds the CDL from `alu_rt_pwr.v`** (the netlist *with* VDD/GROUND pins), not
`alu_rt_sim.v`. Routing emits three files and they are not interchangeable: `_rt.def`,
`_rt_pwr.v` (supply pins → LVS), `_rt_sim.v` (no supply pins → gate-level sim).

⚠️ `cdl_gds_script.source` **re-sources the PDK environment internally**, which can
override what you set in your shell. If a report later points somewhere unexpected, that
is why.

In KLayout:

1. **View → Grid → 5 nm.**
2. Technology dropdown **(Default)** → **scl_cp8d**.
3. **Tools → DRC** → `$KLAYOUT_PATH/tech/drc/drc.lydrc`
4. **Tools → LVS** → `$KLAYOUT_PATH/tech/lvs/lvs.lylvs`

⚠️ **The deck paths carry a `tech/` level.** `$KLAYOUT_PATH/drc/...` does not exist.

🔴 **The DRC report path is CWD-relative with no override** — the deck writes
`./scl_drc.txt` wherever you are standing. SCL expects `5_klayout/lvs_drc/scl_drc.txt`. Run
it from inside the PDK tree and you will **overwrite the PDK's own `scl_drc.txt`**; two
designs checked from one directory silently clobber each other. We hit this.

🔴 **Before believing any KLayout report, read its header:** `<original-file>`,
`<top-cell>`, `<generator>`. All three can silently be wrong. Check `<generator>` against
`$PDK_ROOT` — if they differ you have two PDK trees and must prove they are identical
before trusting the result. **You have two PDK copies** (`~/scl_pdk/...` and `~/pdks/...`),
so this applies to you directly.

Benign warnings to expect: `FOREIGN name SPAD00 differs from MACRO ASPAD00` (a bug in
`pads_cp8d.lef`), and an LVS banner saying **"SCL C1D ... runset"** while running CP8D —
stale header text copied from the 1.2 µm kit, not the wrong deck.

### What "clean" does and doesn't mean

🔴 **Router DRC ≠ signoff DRC.** A 0-byte `drc.rpt` means the *router's* check passed
against the **LEF abstract, which contains no poly**. KLayout flattens the real GDS. On our
design, router DRC was clean while KLayout found real violations — boron-width at cell
abutments, and via-over-poly where long nets cross cells. Both statements are true; they
describe different views. **Never write "DRC clean" without the word *router* unless
KLayout says so.**

⚠️ **A KLayout item count is not a defect count.** An 8-item report on our design was
**5 real vias** — three flagged twice, once per edge of the same via, separated by exactly
the via width. Parse the edge-pairs before quoting a number.

SCL's note says to fix remaining errors by hand per "Annexure-1" — ⚠️ **CP8D ships no flow
annexure.** The referenced document does not exist in this kit.

---

## (G) Post-layout simulation

Add SDF annotation to your testbench:

```verilog
initial begin
  $sdf_annotate(".../runs/RUN/results/sta/alu.sdf", uut);
end
```

then run `tb_postlay_script.source` from `6_iverilog_postlayout/tb_postlay_sim`. Use
`alu_rt_sim.v` (no supply pins) so it binds to your testbench. **Never done by us.**

---

## (H) / (I) KLayout and OpenROAD GUIs

```bash
cd ~/OpenLaneRepo/designs/project_scl_cp8d && source cp8d_pdk_env_setting.source
klayout -e &
```

OpenROAD GUI: `make mount …` as in §E, then `openroad` and `gui::show` inside the
container.

---

## (J) Pad frame integration

Nine manual KLayout steps: open your GDS, copy the chosen `frame#mmx#mm.gds` from
`PadFrame_cp8d/Padframe_database/pad_frame_gds/`, DRC/LVS **the frame alone first**, new
top layout (top cell name == gds name), frame at (0,0), core centred with origin above
(500,500), connect signals to pads, top CDL whose `.subckt` matches the top layout.

⚠️ Pin placement is **accidental** on this flow because `FP_PIN_ORDER_CFG` never applies
(§C), and bonding is 1:1 with pin-out — fix that first.
⚠️ `Padframe_database/report/` holds **PNG screenshots**, not machine-readable reports.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `child killed: kill signal` in `gpl.tcl` | SIGKILL from outside the process | §0.2 — diagnose first. **Not** a density problem |
| `.wslconfig` edits do nothing | `wsl.exe --shutdownn` typo | `wsl --shutdown`, then `free -h` |
| `dmesg` shows no OOM | may not be memory at all | §0.2 (c)/(d) — watch `docker stats` live |
| `flow.tcl: not found` | the EDA-Tools-Installer tree isn't an OpenLane checkout | use `~/OpenLaneRepo` |
| PDK "not found" / missing `config.tcl` / missing `tech_cp8d.lef` | half-built symlink tree | §0.4 — copy, don't link |
| A step works, then stops in a new terminal | env not re-sourced | `source cp8d_pdk_env_setting.source` |
| `$PDK_ROOT` wrong | `OPENLANE_PATH` / `MY_DTECH_DIR_PATH` not edited | §B |
| TritonCTS error | only on combinational designs | §E.1 — not your case |
| `filler_placement.tcl: no such file` | SCL's README names a file the kit doesn't ship | §E.1 — `cts_cp8d.tcl` covers you |
| Placement overlap / row errors | 25.35 vs 32.35 SITE mismatch | §0.6 — do **not** set 25.35 |
| Stage "succeeded", next one fails | nothing printed on success; dead stages leave 0-byte files | check artefact **sizes** |
| `grep … logs/placement/…` finds nothing | `3_src` bypasses the native reporting tree | read `results/` |
| `runs/run9` empty after `-tag run9` | scripts hardcode `runs/RUN` | §E |
| KLayout report shows the wrong design | header lies, or CWD-relative output clobbered | read `<original-file>` / `<generator>` |
| Glacially slow | tree on `/mnt/c/` | §0.3 |

---

## 10. What never goes into a git repository

- `*.lib`, `*.lef` (`tech_cp8d.lef`, `core_cp8d.lef`, `pads_cp8d.lef`, `corner_cp8d.lef`)
- `*.lydrc`, `*.lylvs`, `*.tech`, `*.drc`, any cell GDS, `core_iolib_cp8d.cdl`
- the PDK zips or any part of the kit tree
- **`runs/*/tmp/`** — `merged.{nom,min,max}.lef` + several `.lib` ≈ **14.5 MB of PDK per
  run tree**. The realistic accident; easy to miss in an `rsync`.

⚠️ `rsync --exclude='*.bak'` also matches the **directory** `RUN.bak/`. Use explicit paths.

**Fine to commit:** the `3_src` scripts, `config.json`, `pin_order.cfg`, and all run
outputs — netlist, DEFs, SPEF, SDF, STA reports, `drc.rpt`. They describe the design and
the flow, not the PDK. Cell *names* in a netlist are not PDK data.

---

## 11. Process note

CP8D is **0.8 µm = 800 nm**, a ~1990s node — an educational/open kit with **two metal
layers**. That is why every `add_pdn_stripe -layer metal2` line in `pdn_cp8d.tcl` is
commented out, and why your `FP_PDN_VERTICAL_LAYER: metal2` was a trap rather than a
tuning choice (§0.5). In a 6–10 metal process you strap power on upper layers and never
notice; at 2 metals power and signal compete for the same tracks. **That tradeoff is one of
the better things to be able to explain about a CP8D project.**

---

*Companion documents in this repo:* `docs/flow-notes.md` · `docs/engineering-notes.md` ·
`docs/signoff.md` · `docs/determinism.md` · `docs/failed-runs.md` ·
`docs/scl-pdk-caveats.md`.
