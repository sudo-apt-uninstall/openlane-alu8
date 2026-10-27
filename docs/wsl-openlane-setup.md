# OpenLane + SCL CP8D PDK on WSL2 — setup guide

**Written for Sai Darshan**, setting up an independent parallel run of the `alu8` design
on **Windows + WSL2**, same RTL as this repository, using the **`3_src` flow that ships
inside the SCL CP8D kit**.

This guide follows the kit's own procedure in `Readme_0.8u_digital.txt` — its section
letters **(A)–(J)** are preserved below so you can cross-reference. Everything marked
🪟 is WSL-specific and is **not** in SCL's README; everything else is the shipped
procedure, with the traps we hit annotated.

**SCL's tested toolchain** (from the kit README — match it):

| | version |
|---|---|
| OS | **Ubuntu 22.04.5 LTS** |
| Python | **3.10.12** |
| OpenLane | **1.0.X** |
| KLayout | **0.30.5** |

Our reference runs used OpenLane **v1.0.2**, image
`ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64`.

> **PDK distribution.** This guide contains **no PDK content** — only paths, variable
> names and procedure. Never commit a PDK file to any repository: not `.lib`, not
> `.lef`, not the tech/DRC/LVS decks, not cell GDS, not the kit zip, and not any run
> tree's `tmp/` (which carries ~14.5 MB of merged PDK per run). See §10.

---

## 🪟 0. WSL2 first — this is your current bug

### 0.1 Install WSL2

Administrator PowerShell:

```powershell
wsl --install -d Ubuntu-22.04
wsl --set-default-version 2
wsl --status            # confirm "Default Version: 2"
```

Ubuntu 22.04 is not merely convenient here — it is **the version SCL developed and tested
the kit on**. The README says so explicitly: *"choosing Ubuntu 22.04 LTS will give you the
most out-of-the-box, error-free experience."*

### 0.2 🔴 Raise the memory limit — this is why your run died

**WSL2 defaults to 50 % of host RAM, and the Linux OOM killer inside WSL sends SIGKILL to
the biggest process when that ceiling is hit.** OpenROAD's global placer is that process:

```
[INFO GPL-0028] BinCnt: 16 16
[NesterovSolve] Iter: 1 overflow: 0.864376 HPWL: 45020962
child killed: kill signal
```

Tcl prints **"child killed: kill signal" only for SIGKILL**. SIGTERM prints "software
termination signal"; Ctrl-C prints "interrupt signal". Nothing in OpenROAD, OpenLane or
the PDK sends SIGKILL to itself — it always comes from **outside** the process.

Your log shows the placer was *healthy* up to that instant: bins built (16×16 = 256 vs
IdealBinCnt 331), iteration 1 at a normal overflow of 0.864. It did not fail — it was
killed. Utilisation checks out too: AveragePlaceInstArea 4,611,525,304 × ~210 cells ÷
TotalBinArea 2,549,036,295,000 ≈ **38 %**, so your `DIE_AREA`/`CORE_AREA` are sanely
scaled and the classic wrong-units blunder is ruled out.

🔴 **SCL's README Note 2 says *"If placement, routing fails user need to rerun script
after changing the value of density and area in config.json."* That advice does NOT apply
to your failure.** It is for a placer that *legitimately* cannot fit the design. Yours was
killed by the host. Changing density will not help and will waste your time.

Create `C:\Users\<you>\.wslconfig`:

```ini
[wsl2]
memory=12GB          # at least 8GB; 12-16GB if the host has 32GB
processors=6
swap=8GB
localhostForwarding=true
```

```powershell
wsl --shutdown
```

Verify inside WSL, then confirm the diagnosis:

```bash
free -h                                    # MemTotal reflects .wslconfig
nproc
dmesg -T | grep -iE 'oom|killed process'
```

**Never run two OpenLane flows concurrently on one WSL2 instance.** They do not coordinate
memory; the kernel resolves the contention by killing one. If yours was parallel to
another run, serialise them and the identical config should simply pass.

⚠️ The two trailing `[WARNING]` lines in your log about `scl_cp8d` / `digital_cp8d`
instantiated stdcells are a **red herring**. OpenLane always appends "the failure may have
been because of the following warnings" with whatever it collected; that one is emitted at
synthesis and the flow reached Step 6. Do not go disabling `QUIT_ON_LINTER_ERRORS`.

### 0.3 🪟 Docker

**(a) Docker Desktop** — enable *Settings → Resources → WSL Integration* for Ubuntu.
Memory is governed by `.wslconfig`, **not** Docker Desktop's own slider (that is for the
Hyper-V backend and does nothing for WSL2).

**(b) Docker Engine inside WSL**:

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg make git python3 python3-pip iverilog gtkwave
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
sudo service docker start
```

Reopen the terminal (group membership is read at login), then `docker run --rm hello-world`.

`Cannot connect to the Docker daemon` → `sudo service docker start` again; without systemd
WSL does not auto-start it. To enable systemd, add to `/etc/wsl.conf` and `wsl --shutdown`:

```ini
[boot]
systemd=true
```

### 0.4 🔴🪟 Work in the Linux filesystem, never `/mnt/c/`

SCL's README says *"It is highly recommended to install the OpenLane tool directly in your
Home directory (`~/`)"* — on WSL that is not a recommendation, it is a requirement. `/mnt/c`
is a 9P network mount: an order of magnitude slower for OpenLane's many small file
operations, and Linux file modes do not survive it, which breaks bind-mounted scripts
inside the container. Browse from Windows the other way:
`\\wsl$\Ubuntu-22.04\home\<you>` in File Explorer.

Everything below assumes `~/OpenLane` and `~/my_dtech_cp8d`, the kit's defaults.

### 0.5 🪟 KLayout — install 0.30.5, not the apt package

`apt install klayout` on Ubuntu 22.04 gives a much older release than the **0.30.5** SCL
tested against. Get the `.deb` from <https://www.klayout.de/build.html> (Ubuntu 22.04,
amd64) and:

```bash
sudo apt install -y ./klayout_0.30.5-1_amd64.deb
klayout -v
```

For the GUI you need X. **WSLg** (Windows 11, or Win10 with a recent WSL kernel) works with
no configuration. Older setups: install VcXsrv/X410 and
`export DISPLAY=$(ip route show default | awk '{print $3}'):0`.

The flow **requires** the KLayout GUI — SCL's DRC and LVS steps (§F) are menu-driven.

---

## (A) PDK integration

1. Extract `my_dtech_cp8d.zip` and move the **`my_dtech_cp8d`** folder into `~/`.

2. Inside it, navigate to:

```
~/my_dtech_cp8d/Open_Source_SCL_0.8micron_PDK_digital/open_source_scl_cp8d/open_pdks/scl_cp8d/libs.ref/digital_cp8d/project_scl_cp8d
```

3. **Copy that whole `project_scl_cp8d` folder into `~/OpenLane/designs/`.**

```bash
cp -r ~/my_dtech_cp8d/Open_Source_SCL_0.8micron_PDK_digital/open_source_scl_cp8d/open_pdks/scl_cp8d/libs.ref/digital_cp8d/project_scl_cp8d ~/OpenLane/designs/
```

4. If either `my_dtech_cp8d` or `OpenLane` is **not** in your home directory, edit
   `cp8d_pdk_env_setting.source` inside that folder (see next section).

⚠️ **There is no `sclenv` and no `olmount` in this kit.** Those are local aliases on our
machine — if you saw them in an earlier version of this document, ignore them. The kit
ships `cp8d_pdk_env_setting.source` and uses plain `make mount`.

---

## (B) Environment and project directory setup

### The environment script

`~/OpenLane/designs/project_scl_cp8d/cp8d_pdk_env_setting.source` is **sourceable** —
unlike our local wrapper. It sets exactly five things:

```bash
export HOME=~
export OPENLANE_PATH="$HOME/OpenLane"
export MY_DTECH_DIR_PATH=$HOME/my_dtech_cp8d          # <-- edit if elsewhere
export PDK_ROOT=$MY_DTECH_DIR_PATH/Open_Source_SCL_0.8micron_PDK_digital/open_source_scl_cp8d/open_pdks
export PDK=scl_cp8d
export KLAYOUT_PATH=$PDK_ROOT/$PDK/libs.tech/klayout
```

Only `OPENLANE_PATH` and `MY_DTECH_DIR_PATH` are meant to be edited. Note the variable is
**`MY_DTECH_DIR_PATH`**, not `MY_DTECH_DIR`.

```bash
cd ~/OpenLane/designs/project_scl_cp8d
source cp8d_pdk_env_setting.source
```

It prints `HOME`, `MY_DTECH_DIR`, `PDK_ROOT`, `PDK`, `OPENLANE_PATH`. **Read them and
check they are real paths.**

🔴 **You must re-source this in every new terminal window.** SCL says so explicitly, and
it is the single most common reason a step mysteriously stops working.

⚠️ **Never source a Cadence environment into the same shell.** Both set `PDK_ROOT`, and the
collision is silent — you end up checking your design against the wrong PDK. Keep a
dedicated terminal for this flow. (Not an issue on a fresh WSL box, but worth knowing.)

### Create your project

```bash
cd ~/OpenLane/designs/project_scl_cp8d
cp -r sample_project_files_cp8d alu8
cd alu8
```

You now have the shipped skeleton:

```
alu8/
├── 1_RTL/                          <-- your RTL goes here
├── 2_iverilog_prelayout/tb_prelay_sim/tb_prelay_script.source
├── 3_src/                          <-- TEN tcl scripts, see below
├── 4A_synthesis_netlist/
├── 4B_synthesis_netlist_sim/tb_prelay_sim/tb_sys_sim_script.source
├── 5_klayout/
│   ├── cdl_gds_script.source
│   ├── lvs_drc/
│   └── script/{def2gds.py, verilog2spice.py}
├── 6_iverilog_postlayout/tb_postlay_sim/tb_postlay_script.source
├── config.json
└── pin_order.cfg
```

**`3_src` ships exactly ten scripts:** `yosys_script.tcl`, `floorplan_cp8d.tcl`,
`pdn_cp8d.tcl`, `pdn_order.tcl`, `placement_cp8d.tcl`, `cts_cp8d.tcl`,
`routing_cp8d.tcl`, `rcx_cp8d.tcl`, `run_sta.tcl`, `script_openlane.tcl`.

### Put the RTL in place

🔴 **The RTL file must be `.v`.** SCL's step 8: *"Create your Verilog RTL file with a `.v`
extension and save it inside the `1_RTL` folder."* `yosys_script.tcl` hardcodes
`$::env(DESIGN_NAME).v`.

`alu8.sv` in this repository is SystemVerilog. Two things to do:

```bash
cp <path>/alu8.sv ~/OpenLane/designs/project_scl_cp8d/alu8/1_RTL/alu8.v
```

and edit `3_src/yosys_script.tcl` line 2 to add **`-sv`** to `read_verilog`. ⚠️ The `.v`
extension now lies about the contents — note it in your own README so you don't forget.

---

## (C) Configuration

The shipped `config.json`:

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

**For `alu8`, change it to:**

```json
{
    "DESIGN_NAME": "alu8",
    "DESIGN_TOP_CELL_NAME": "alu8",
    "DIE_AREA": "0 0 1000 1000",
    "CORE_AREA": "100 100 900 900",
    "CLOCK_PERIOD": 100,
    "CLOCK_PORT": "",
    "CLOCK_NET": "",
    "RUN_CTS": false,
    "PL_TARGET_DENSITY": 0.45,
    "FP_PIN_ORDER_CFG": "dir::pin_order.cfg",
    "FP_PDN_SKIPTRIM": true,
    "PLACE_SITE": "CORE",
    "PLACE_SITE_WIDTH": 3.9,
    "PLACE_SITE_HEIGHT": 32.35
}
```

Notes on each change:

- **`DESIGN_NAME` == `DESIGN_TOP_CELL_NAME` == `alu8`.** The sample splits them
  (`test` / `test_top`) and so does SCL's `cnt8`; our ALU does not — the module is just
  `alu8`. Get this wrong and floorplan cannot find the top cell.
- **`CLOCK_PORT ""` / `CLOCK_NET ""` / `RUN_CTS false`** — `alu8` is purely combinational.
  See §E.
- **`DIE_AREA` 1000 and `CORE_AREA` 100..900** — the design is tiny (~0.137 mm² of cell
  area at ~1 % utilisation). 5000 works too but wastes an enormous amount of filler.
- **`CLOCK_PERIOD` 100 is a placeholder** and only reaches STA — see §E.3.
- **`PLACE_SITE_HEIGHT 32.35`** — see §E.4. **Never set it to 25.35.**

Then edit `pin_order.cfg` for the 29 `alu8` pins. The one in this repo groups them
`#N a[.*]` · `#S b[.*]` · `#W op[.*]` · `#E result[.*] zero carry`.

⚠️ **`FP_PIN_ORDER_CFG` has no effect on this flow.** `floorplan_cp8d.tcl` contains no
`place_pins` call; the only one is in `routing_cp8d.tcl`, unconstrained, *after*
placement. The variable is read into the environment and never used. Write the file
anyway — it documents intent, and it matters the moment you integrate a pad frame (§J).

---

## (D) RTL simulation in Icarus Verilog

Worth doing, and **we never did it** — it is the biggest gap in our own run. If you
complete it you will have something we don't.

```bash
cd ~/OpenLane/designs/project_scl_cp8d/alu8/2_iverilog_prelayout/tb_prelay_sim
# put tb_alu8.v here (rename from .sv), then edit the four variables in:
#   PROJECT_NAME, DESIGN_NAME, DESIGN_TOP_CELL_NAME, TESTBENCH_TOP_CELL_NAME
source tb_prelay_script.source
```

`tb_alu8.sv` is in this repo under `rtl/`.

---

## (E) OpenLane RTL-to-DEF flow

```bash
cd ~/OpenLane/designs/project_scl_cp8d
source cp8d_pdk_env_setting.source      # EVERY new terminal
cd ~/OpenLane
make mount PDK_ROOT=$MY_DTECH_DIR_PATH/Open_Source_SCL_0.8micron_PDK_digital/open_source_scl_cp8d/open_pdks PDK=scl_cp8d
```

Inside the container:

```bash
cd /openlane
./flow.tcl -design project_scl_cp8d/alu8 -tag RUN -interactive
```

That gives a **`%` Tcl prompt — not bash.** Then run the stages:

```tcl
run_yosys_script    $::env(DESIGN_DIR)/3_src/yosys_script.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/floorplan_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/pdn_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/placement_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/fill_cp8d.tcl     ;# NOT cts — see E.1
run_openroad_script $::env(DESIGN_DIR)/3_src/routing_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/rcx_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/run_sta.tcl
```

🔴 **`run_openroad_script` and `run_yosys_script` take a PATH argument.** A bare call fails.

🔴 **`run_openroad_script` prints nothing on success.** Check `results/`, not the terminal.
A dead stage can leave a **0-byte** artefact that looks present — this cost us a wrong
root-cause investigation. **Check sizes, not existence.**

⚠️ **`-tag XYZ` does not do what you expect.** Every `3_src` script hardcodes `runs/RUN` in
its output paths, so `-tag CHIP` creates `runs/CHIP` for OpenLane's bookkeeping while every
stage writes into `runs/RUN` anyway, silently overwriting it. For a second configuration:
`mv runs/RUN runs/RUN_<name>` first, swap `config.json`, run as `-tag RUN`, rename after.

⚠️ `-overwrite` deletes **all** of `runs/RUN`. SCL's README warns to back up `runs/RUN` and
`4A_synthesis_netlist` first. Also copy `5_klayout/` out — it is not in `runs/`, but a
re-run regenerates over it.

### E.1 🔴 The combinational problem — and the file SCL forgot to ship

SCL's README, Note 1, verbatim:

> *"If your design is a purely combinational circuit or a ring oscillator, skip the
> `cts_cp8d.tcl` script and run `filler_placement.tcl` instead to avoid TritonCTS errors."*

**`filler_placement.tcl` is not in the kit.** `3_src` ships ten scripts and that is not one
of them. The step is mandatory and the file is missing — you have to write it.

Why it matters, concretely:

- `placement_cp8d.tcl` ends at `detailed_placement` + `check_placement`. It has **no**
  `filler_placement` call.
- `cts_cp8d.tcl` is the **only** shipped script that calls `filler_placement` — after its
  clock-tree work, which is exactly the part that crashes with no clock.
- **CP8D ships no tap/welltap cell.** At 0.8 µm the well and substrate contacts are drawn
  inside every standard cell *and inside the fillers*, so **filler insertion IS the tap
  strategy on this process**. Skip it and you get broken nwell/implant continuity and
  signoff DRC failures — not a cosmetic area fill.

Our substitute is `flow/3_src/fill_cp8d.tcl` in this repository. It writes to the **same
`results/cts/` paths** `cts_cp8d.tcl` would, so `routing_cp8d.tcl` needs no edit at all.
Copy it into your `3_src/`. Its shape:

```tcl
read_liberty .../cp8d_core_typ.lib
read_lef     tech_cp8d / core_cp8d / pads_cp8d / corner_cp8d
read_db      ".../results/placement/${DESIGN_NAME}_plcts.odb"
set_cmd_units -time ns -capacitance pF -resistance kOhm -voltage V -current mA
detailed_placement
set ::env(FP_FILL_CELL) "FILLER1 FILLER2 FILLER3 FILLER4 FILLER5 FILLER6"
filler_placement -prefix FILLER [list "FILLER1" ... "FILLER6"]
write_db  ".../results/cts/${DESIGN_NAME}_plcts.odb"
write_def ".../results/cts/${DESIGN_NAME}_plcts.def"
```

🔴 **Never run `cts_cp8d.tcl` on `alu8`** — it does `[get_ports clk]`, and there is no
clock port.

### E.2 🔴 `script_openlane.tcl` cannot be used as shipped

The batch runner SCL offers:

```tcl
source $::env(DESIGN_DIR)/3_src/script_openlane.tcl
```

contains, verbatim, eight lines — and line 5 is **`run_openroad_script
$::env(DESIGN_DIR)/3_src/cts_cp8d.tcl`**. On a combinational design it will take you
straight into the TritonCTS failure Note 1 warns about.

**Copy it, swap that one line for `fill_cp8d.tcl`, and run your copy.** (It also omits
`pdn_order.tcl`, which the kit ships but never calls — leave that alone.)

### E.3 `CLOCK_PERIOD` never reaches synthesis

`abc -liberty` is called with no `-D` and no SDC, so ABC maps for **area**, not timing.
`CLOCK_PERIOD` only feeds `create_clock` in `run_sta.tcl`. A full re-run to "get
timing-driven synthesis" buys nothing — **re-run `run_sta.tcl` alone.** This also explains
why the adder maps to a gate carry chain rather than `ADR100`: an area-mode choice, not a
library mystery.

You must also edit `run_sta.tcl`: as shipped it does
`create_clock -name CLK -period $::env(CLOCK_PERIOD) [get_ports clk]`, which **errors**
with no `clk` port. Replace with a virtual clock and zero I/O delays:

```tcl
create_clock -name vclk -period $::env(CLOCK_PERIOD)
set_input_delay  0.0 -clock vclk [all_inputs]
set_output_delay 0.0 -clock vclk [all_outputs]
```

OpenSTA then reports pure input-to-output combinational delay against the window.

### E.4 The floorplan deletes every odd row — do not "fix" it

`floorplan_cp8d.tcl` contains:

```tcl
foreach row $block { if {[expr $count % 2] != 0} { odb::dbRow_destroy $row }; incr count }
```

The tech LEF declares a SITE height of **25.35** while the cells are **32.35** tall, so
`initialize_floorplan -site CORE` builds **overlapping** rows and SCL works around it by
destroying every second one. 25.35 × 2 = **50.70 µm**, exactly the row pitch you will
observe. 18.35 µm of every row is dead space (36 % wasted) — harmless at ~1 % utilisation,
but it means **no density figure from this flow is meaningful**.

**`PLACE_SITE_HEIGHT 32.35` is correct.** Un-flipped rows at 25.35 pitch would lay one
row's VDD rail across the next row's GROUND rail: a short. The datasheets confirm 32.35 is
the true cell height; the LEF's 25.35 is the abutment box, and 3.5 µm of overhang top and
bottom accounts for the difference.

### E.5 Expected results (our 1 mm reference)

| stage | artefact | size |
|---|---|---|
| yosys | `results/synthesis/alu8_sys.v` | 20,959 B — **210 CP8D cells** |
| floorplan | 16 rows at 50.7 µm pitch, ~33 % occupancy | |
| placement | `results/placement/alu8_pl.def` | |
| fill | `results/cts/alu8_plcts.def` | 566 components = 210 logic + **356 FILLER** |
| routing | `results/routing/alu8_rt.def` | **319,149 B** |
| | `results/routing/drc.rpt` | **0 bytes = router DRC pass** |
| rcx | `results/spef/alu8.spef` | 155,176 B |
| sta | `results/sta/timing_report.txt` | setup **11.61 ns**, slack +88.39 MET; hold +0.78 MET |

`drc.rpt` is the one artefact where **0 bytes means success**.

The flow is deterministic — our re-runs reproduce these byte-for-byte, through signoff. If
your `alu8_rt.def` is not 319,149 B, **an input differs**; find it before interpreting any
result. Start with the synthesis cell count: it should be **210**.

⚠️ STA writes to `results/sta/`, **not** `reports/`. `runs/RUN/reports/` and `logs/` stay
empty forever, because raw `run_openroad_script` calls bypass OpenLane's native reporting
tree. Expected, not a failure.

Then `exit` twice to leave the container, as SCL's step 28 says.

---

## (F) DEF-to-GDS, DRC and LVS in KLayout

```bash
cd ~/OpenLane/designs/project_scl_cp8d/alu8/5_klayout
# edit cdl_gds_script.source: PROJECT_NAME, DESIGN_NAME, DESIGN_TOP_CELL_NAME
source cdl_gds_script.source
```

For `alu8` those three become `alu8` / `alu8` / `alu8` (the template ships pointing at the
`cnt8` sample). That is a genuine **input-side edit** — recreate it on any clean checkout.

The script runs `verilog2spice.py` → `alu8.cdl`, `def2gds.py` → `alu8.gds`, then opens
KLayout. Output lands in `5_klayout/lvs_drc/`.

⚠️ **It builds the CDL from `alu8_rt_pwr.v`** (the netlist *with* VDD/GROUND pins), not
`alu8_rt_sim.v`. Routing emits three files and they are not interchangeable: `_rt.def`,
`_rt_pwr.v` (supply pins → LVS), `_rt_sim.v` (no supply pins → gate-level sim).

⚠️ `cdl_gds_script.source` **re-sources the PDK environment** internally, which can
override what you set in your shell. If a report later points somewhere unexpected, this
is why.

In KLayout:

1. **View → Grid → 5 nm.**
2. Switch the technology dropdown from **(Default)** to **scl_cp8d**.
3. **Tools → DRC** → `$KLAYOUT_PATH/tech/drc/drc.lydrc`
4. **Tools → LVS** → `$KLAYOUT_PATH/tech/lvs/lvs.lylvs`

⚠️ **The deck paths carry a `tech/` level.** `$KLAYOUT_PATH/drc/...` does not exist.

🔴 **The DRC report path is CWD-relative with no override** — the deck writes
`./scl_drc.txt` wherever you are standing. SCL expects
`5_klayout/lvs_drc/scl_drc.txt`. Run it from inside the PDK tree and you will **overwrite
the PDK's own `scl_drc.txt`**; two designs checked from one directory silently clobber
each other. We hit this.

🔴 **Before believing any KLayout report, read its header:** `<original-file>`,
`<top-cell>` and `<generator>`. All three can silently be wrong. Check `<generator>`
against `$PDK_ROOT` — if they differ you have two PDK trees and must prove they are
identical before trusting the result.

Two benign warnings to expect: `FOREIGN name SPAD00 differs from MACRO ASPAD00` (a bug in
`pads_cp8d.lef`) and an LVS banner saying **"SCL C1D ... runset"** while running CP8D —
stale header text copied from the 1.2 µm kit, not the wrong deck.

### What "clean" does and doesn't mean

🔴 **Router DRC ≠ signoff DRC.** A 0-byte `drc.rpt` means the *router's* check passed
against the **LEF abstract, which contains no poly**. KLayout flattens the real GDS. On
this exact design, router DRC was clean while KLayout found real violations — boron-width
at cell abutments, and via-over-poly where long nets cross cells. Both statements are true;
they are about different views. **Never write "DRC clean" without the word *router* unless
KLayout says so.**

⚠️ **A KLayout item count is not a defect count.** An 8-item report on this design was
**5 real vias** — three flagged twice, once per edge of the same via, separated by exactly
the via width. Parse the edge-pairs before quoting a number.

SCL's own note: *"If the generated GDS still contains DRC errors, users must fix these
manually based on Annexure-1"* of the digital PDK document. Be aware there is **no flow
annexure for CP8D** — the referenced annexure does not exist in this kit.

---

## (G) Post-layout simulation

Also never done by us. Add SDF annotation to your testbench:

```verilog
initial begin
  $sdf_annotate(".../runs/RUN/results/sta/alu8.sdf", uut);
end
```

then run `tb_postlay_script.source` from `6_iverilog_postlayout/tb_postlay_sim`. Use
`alu8_rt_sim.v` (no supply pins) so it binds to the existing testbench.

---

## (H) / (I) KLayout and OpenROAD GUIs

```bash
cd ~/OpenLane/designs/project_scl_cp8d && source cp8d_pdk_env_setting.source
klayout -e &
```

OpenROAD GUI: `make mount ...` as in §E, then inside the container `openroad` and
`gui::show`. Both need working X — see §0.5.

---

## (J) Pad frame integration

Entirely manual in KLayout: open your GDS, copy the chosen `frame#mmx#mm.gds` from
`PadFrame_cp8d/Padframe_database/pad_frame_gds/`, place the frame at (0,0), place the core
centred above (500,500), connect core signals to pads, and build a top CDL whose `.subckt`
name matches the top layout.

⚠️ Before investing time here: our pin placement is **accidental**, because
`FP_PIN_ORDER_CFG` never applied (§C). Bonding is 1:1 with pin-out, so that has to be fixed
first. Also note `Padframe_database/report/` contains **PNG screenshots**, not
machine-readable reports — ten images, one per die size per check.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `child killed: kill signal` in `gpl.tcl` | SIGKILL from outside — OOM killer / WSL2 cap | §0.2. **Not** a density problem |
| `Cannot connect to the Docker daemon` | no systemd in WSL | `sudo service docker start`, or enable systemd |
| A step works, then stops working in a new terminal | env not re-sourced | `source cp8d_pdk_env_setting.source` again |
| `$PDK_ROOT` empty or wrong | `MY_DTECH_DIR_PATH` not edited | §B |
| TritonCTS error / `[get_ports clk]` | combinational design | §E.1, §E.3 — `fill_cp8d.tcl`, virtual clock |
| `filler_placement.tcl: no such file` | SCL's README names a file the kit doesn't ship | §E.1 — write it |
| Signoff DRC fails on well/implant continuity | fillers missing | §E.1 — fillers *are* the taps here |
| Placement overlap / row errors | 25.35 vs 32.35 SITE mismatch | §E.4 — do **not** set 25.35 |
| Stage "succeeded", next one fails | nothing is printed on success; dead stages leave 0-byte files | check artefact **sizes** |
| `runs/XYZ` empty after `-tag XYZ` | scripts hardcode `runs/RUN` | §E |
| KLayout report shows the wrong design | header lies, or CWD-relative output clobbered | read `<original-file>` / `<generator>` |
| `FOREIGN name SPAD00 differs from MACRO ASPAD00` | known bug in `pads_cp8d.lef` | benign |
| LVS banner says "SCL C1D runset" | stale header from the 1.2 µm kit | benign |
| `PDK 'scl_cp8d' ... instantiated stdcells` warning | synthesis-stage linter | benign on its own; see §0.2 |
| Glacially slow | tree on `/mnt/c/` | §0.4 |

---

## 10. What never goes into a git repository

- `*.lib`, `*.lef` (`tech_cp8d.lef`, `core_cp8d.lef`, `pads_cp8d.lef`, `corner_cp8d.lef`)
- `*.lydrc`, `*.lylvs`, `*.tech`, `*.drc`, any cell GDS, `core_iolib_cp8d.cdl`
- the PDK zips (`my_dtech_cp8d.zip`, the kit archive) or any part of the kit tree
- **`runs/*/tmp/`** — carries `merged.{nom,min,max}.lef` and several `.lib` ≈ **14.5 MB of
  PDK per run tree**. This is the realistic accident; it is easy to miss in an `rsync`.

⚠️ `rsync --exclude='*.bak'` also matches the **directory** `RUN.bak/`, silently skipping
your failure-evidence tree. Use explicit paths.

**Fine to commit:** the `3_src` scripts, `config.json`, `pin_order.cfg`, and all run
outputs — netlist, DEFs, SPEF, SDF, STA reports, `drc.rpt`. They describe the design and
the flow, not the PDK. Cell *names* in a netlist are not PDK data.

---

## 11. Process note

CP8D is **0.8 µm = 800 nm**, a ~1990s node — an educational/open kit with **two metal
layers**. That is why every `add_pdn_stripe -layer metal2` line in `pdn_cp8d.tcl` is
commented out: `routing_cp8d.tcl` pins signals to `metal1-metal2`, so vertical metal2 power
straps would consume the only vertical signal resource. In a 6–10 metal process you strap
on upper layers and never notice. **Do not uncomment them** — and that tradeoff is one of
the better things to be able to explain about a CP8D project.

---

*Companion documents in this repo:* `docs/flow-notes.md` (the combinational-on-CP8D
technique in full), `docs/engineering-notes.md` (status, open items, corrections),
`docs/signoff.md` (KLayout DRC/LVS), `docs/determinism.md` (re-run evidence),
`docs/failed-runs.md` (how to read the error logs in `runs/`),
`docs/scl-pdk-caveats.md` (the kit's known defects).
