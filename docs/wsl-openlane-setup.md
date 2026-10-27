# OpenLane + SCL CP8D PDK on WSL2 — setup guide

**Written for Sai Darshan**, setting up an independent parallel run of the `alu8` design
on **Windows + WSL2**, same RTL as this repository.

**Reference machine for every number quoted here:** W0, **RHEL 9 bare metal**, OpenLane
**v1.0.2**, image digest
`ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64`.
Pin the same image — a different OpenROAD build will not reproduce these results.

> **PDK distribution note.** This guide tells you *how* to install the SCL 0.8 µm (CP8D)
> kit. It contains **no PDK content** — only paths and variable names. Never commit a
> PDK file to any repository: not `.lib`, not `.lef`, not the tech/DRC/LVS decks, not
> cell GDS, not the kit zip, and not any run tree's `tmp/` directory (which silently
> carries ~14.5 MB of merged PDK per run). Obtain the kit from its original source.

---

## 🔴 READ FIRST — there are two different flows, and they are not interchangeable

Everything in sections 5–8 depends on which one you are running.

| | **Path A — OpenLane native** | **Path B — SCL `3_src`** |
|---|---|---|
| How it runs | `./flow.tcl ... -design alu8` and let it drive itself, or `run_placement_step` etc. | `-interactive`, then `run_openroad_script <path>` per stage |
| Scripts used | `/openlane/scripts/openroad/*.tcl` | the design's own `3_src/*.tcl` |
| Your run | **this is what you are on** — your traceback is `run_placement_step` → `global_placement_or` → `scripts/openroad/gpl.tcl` | what every result in this repo came from |
| `config.json` vars | honoured normally | **several are silently ignored** — see §5.3 |
| CTS | runs normally | must be replaced by `fill_cp8d.tcl` (§5.5) |
| Artefact sizes | **will not match this repo's** | the numbers in §7.1 |

**Path A is a legitimate way to run the design.** It is arguably the better-behaved one —
it honours `FP_PIN_ORDER_CFG` and the cell-padding variables, which Path B does not. But
it will produce different DEFs, different placement and possibly different cell counts.

🔴 **Therefore: do not diff your results against this repo's artefacts stage-for-stage.**
If you and the repo want comparable numbers, one of you must switch flows first. Sections
1–4 (the WSL and PDK setup) apply to both, and are the parts you need right now.

---

## 0. The five things that actually go wrong

| # | Trap | Symptom | Path |
|---|---|---|---|
| 1 | **WSL2 default RAM cap** | global placement dies with `child killed: kill signal` | both |
| 2 | **Project tree on `/mnt/c/`** | 10–30× slower, Docker bind-mount permissions break | both |
| 3 | **`PDK_ROOT` collision** | `sclenv` refuses to load, or you silently check against the wrong PDK | both |
| 4 | **`run_openroad_script` with no path argument** | cryptic Tcl error; it *requires* the script path | B |
| 5 | **`-tag XYZ`** | `3_src` scripts hardcode `runs/RUN` and write there anyway | B |

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

### 1.2 🔴 Raise the memory limit — this is your current bug, not an optimisation

**WSL2 defaults to 50 % of host RAM, and the Linux OOM killer inside WSL sends SIGKILL
to the biggest process when that ceiling is hit.** OpenROAD's global placer is that
process. This is exactly what you saw:

```
[INFO GPL-0028] BinCnt: 16 16
[NesterovSolve] Iter: 1 overflow: 0.864376 HPWL: 45020962
child killed: kill signal
```

Tcl prints **"child killed: kill signal" only for SIGKILL**. SIGTERM prints "software
termination signal"; Ctrl-C prints "interrupt signal". Nothing inside OpenROAD, OpenLane
or the PDK sends SIGKILL to itself — it always comes from outside the process. Your log
also shows the placer was *healthy* up to that instant: the bins built (16×16 = 256 vs
IdealBinCnt 331) and iteration 1 reported a normal overflow of 0.864. It did not fail; it
was killed.

The two trailing `[WARNING]` lines about `scl_cp8d` / `digital_cp8d` instantiated stdcells
are a **red herring** — OpenLane always appends "the failure may have been because of the
following warnings" with whatever it collected, and that one is emitted at synthesis. The
flow reached Step 6, so it did not stop anything. Do not go disabling
`QUIT_ON_LINTER_ERRORS` over it.

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

Confirm the diagnosis before changing anything else:

```bash
dmesg -T | grep -iE 'oom|killed process'
```

**Never run two OpenLane flows concurrently on one WSL2 instance.** They do not coordinate
memory; the kernel resolves the contention by killing one of them. If your run was
parallel to another, serialise them and the identical config should simply pass.

### 1.3 Docker

**(a) Docker Desktop for Windows** — enable *Settings → Resources → WSL Integration* for
your Ubuntu distro. Memory is governed by `.wslconfig` above, **not** by Docker Desktop's
own memory slider (that slider is for the Hyper-V backend and does nothing for WSL2).

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

`Cannot connect to the Docker daemon` → run `sudo service docker start` again; without
systemd, WSL does not auto-start it on boot. To enable systemd instead, add to
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

`/mnt/c` is a 9P network mount — an order of magnitude slower for the many small file
operations OpenLane does, and Linux file modes do not survive it, which breaks
bind-mounted scripts inside the container. To browse from Windows, go the other way:
`\\wsl$\Ubuntu-22.04\home\<you>\eda` in File Explorer.

---

## 2. Install OpenLane v1.0.2

```bash
cd ~/eda
git clone https://github.com/The-OpenROAD-Project/OpenLane.git
cd OpenLane
git checkout v1.0.2
```

Pull the exact image:

```bash
export OPENLANE_IMAGE_NAME=ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64
docker pull $OPENLANE_IMAGE_NAME
```

**Do not run OpenLane's `make` PDK bootstrap.** It installs sky130/gf180 via `volare`. We
are not using those — the SCL kit ships its own `open_pdks` tree and `PDK_ROOT` must point
at it. Installing sky130 is harmless but wastes several GB and creates a second `PDK_ROOT`
you can accidentally pick up.

Smoke-test the container only:

```bash
docker run --rm -it $OPENLANE_IMAGE_NAME bash -lc 'yosys -V; openroad -version'
```

---

## 3. Install the SCL CP8D PDK

Obtain `SCL_CP8D_PDK_v1` (0.8 µm) from Deepesh / its original source and unpack it inside
the WSL filesystem. Do not fetch it from a public mirror and do not re-publish it.

```bash
mkdir -p ~/eda/pdk && cd ~/eda/pdk
unzip "SCL_0.8 um PDK.zip"       # produces SCL_CP8D_PDK_v1/
```

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
    └── Padframe_database/              <-- pad frame GDS + DRC/LVS screenshots
```

### 3.1 The environment, and the one rule about it

The kit ships a launcher called `sclenv`, which sets in effect:

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
`--rcfile`. `source sclenv` from a shell that already has variables set gives you
`$PDK_ROOT` expanding to `//` and nothing works. **Run `sclenv` first, then work in the
shell it hands you.**

🔴 **`sclenv` refuses to load if `$CADENCE_ROOT` and `$DDIROOT` are set** — both the
Cadence environment and `sclenv` set `PDK_ROOT`, and the collision is silent and
destructive. Use a **dedicated terminal** and never source the Cadence environment into
it. On a fresh WSL box you have no Cadence, so this bites later rather than now — but it
is the commonest way to end up checking a design against the wrong PDK.

Edit `sclenv`'s `MY_DTECH_DIR` and `OPENLANE_PATH` to your WSL layout, then:

```bash
sclenv
echo "$PDK_ROOT"        # must print a real path, not //
ls "$PDK_ROOT/scl_cp8d/libs.tech/klayout/tech/drc/"
```

⚠️ **The KLayout deck paths carry a `tech/` level**: `$KLAYOUT_PATH/tech/drc/drc.lydrc`
and `$KLAYOUT_PATH/tech/lvs/lvs.lylvs`. `$KLAYOUT_PATH/drc/...` does not exist.

---

## 4. Install KLayout (signoff DRC/LVS) — host side, not in the container

The OpenLane image does **not** carry the SCL KLayout decks, and signoff runs outside the
flow on both paths.

```bash
sudo apt install -y klayout
klayout -v
```

For the GUI you need X. WSLg (Windows 11, or Win10 with a recent WSL kernel) works with no
configuration — just run `klayout`. Older setups: install VcXsrv/X410 and
`export DISPLAY=$(ip route show default | awk '{print $3}'):0`.

Batch DRC, once you have a GDS:

```bash
klayout -b -r "$KLAYOUT_PATH/tech/drc/drc.lydrc" -rd input=alu8.gds -rd topcell=alu8
```

🔴 **The DRC report path is CWD-relative with no override.** The deck writes
`./scl_drc.txt` into whatever directory you are standing in. Run it from inside the PDK
tree and you **overwrite the PDK's own `scl_drc.txt`**; two designs checked from one
directory silently clobber each other. Run DRC from a scratch directory and move the
report out.

🔴 **Before believing any KLayout report, read its header:** `<original-file>`,
`<top-cell>` and `<generator>`. All three can silently be wrong. Check `<generator>`
against `$PDK_ROOT` — if they differ you have two PDK trees and must prove they are
identical before trusting the result.

---

## 5. The design — and what changes per path

```bash
cd ~/eda/OpenLane/designs
mkdir -p project_scl_cp8d/alu8
```

The RTL is `rtl/alu8.sv` in this repository. Everything below is about how each path
treats it.

### 5.1 Minimum `config.json` — applies to both paths

```
DESIGN_NAME            alu8
DESIGN_TOP_CELL_NAME   alu8
DIE_AREA               "0 0 1000 1000"
CORE_AREA              "100 100 900 900"
CLOCK_PORT             ""          <-- combinational design, see 5.4
CLOCK_NET              ""
RUN_CTS                false
CLOCK_PERIOD           100         <-- placeholder; see 5.6
PLACE_SITE             "CORE"
PLACE_SITE_WIDTH       3.9
PLACE_SITE_HEIGHT      32.35       <-- never change to 25.35, see 5.7
PL_TARGET_DENSITY      0.45
```

### 5.2 🔴 Path A specifics (your flow)

Run it the ordinary way:

```bash
sclenv
olmount
cd /openlane
./flow.tcl -design project_scl_cp8d/alu8 -tag myrun
```

**On Path A, these config variables are live** and are your real tuning levers — they are
*dead* on Path B, so nobody in this repo has ever exercised them on this design:

- `PL_TARGET_DENSITY` — fed to `gpl.tcl`. Your log shows `TargetDensity: 0.60`.
- `FP_PIN_ORDER_CFG` — the native floorplan step actually calls `place_pins` with it.
- `GPL_CELL_PADDING` / `DPL_CELL_PADDING` — the native placement step applies them via
  `set_placement_padding`. **Units are site widths, not µm** (1 site = 3.9 µm).
- `DRC_EXCLUDE_CELL_LIST` / `..._OPT` — consumed by the native Magic/KLayout steps.

**You can keep `.sv` on Path A.** The `.v` rename in §5.3 is a Path B artefact.

**Sanity check from your own log:** AveragePlaceInstArea 4,611,525,304 × ~210 cells ÷
TotalBinArea 2,549,036,295,000 ≈ **38 % utilisation**. That is coherent, so your die/core
is correctly scaled — the classic "DIE_AREA in the wrong units" blunder is ruled out.

### 5.3 Path B specifics — the seven input-side edits

Skip this section entirely if you stay on Path A. These exist because `run_openroad_script`
calls the design's own `3_src/*.tcl` and bypasses OpenLane's native steps:

1. **`1_RTL/alu8.v`** — the SystemVerilog file **renamed** to `.v`, because
   `yosys_script.tcl` hardcodes `$::env(DESIGN_NAME).v`. ⚠️ The extension lies.
2. **`3_src/yosys_script.tcl` line 2** — `-sv` added to `read_verilog`.
3. **`config.json`** — as §5.1.
4. **`pin_order.cfg`** — 29 pins, N/S/W/E grouped. ⚠️ **Never actually applied on Path B**
   (no `place_pins` in `floorplan_cp8d.tcl`); it works on Path A.
5. **`3_src/run_sta.tcl`** — virtual clock (§5.4).
6. **`3_src/fill_cp8d.tcl`** — CTS substitute (§5.5). SCL's README mandates the step and
   the kit never ships the file.
7. **`5_klayout/cdl_gds_script.source`** — three lines retargeted from the `cnt8` template.

All of these are in this repo under `flow/`.

### 5.4 Combinational design = no clock port (both paths)

The stock `run_sta.tcl` does `create_clock ... [get_ports clk]`, which **errors** with no
`clk` port. Use a virtual clock and zero I/O delays:

```tcl
create_clock -name vclk -period $::env(CLOCK_PERIOD)
set_input_delay  0.0 -clock vclk [all_inputs]
set_output_delay 0.0 -clock vclk [all_outputs]
```

OpenSTA then reports pure input-to-output combinational delay against the window.
🔴 **Never run `cts_cp8d.tcl`** on this design — same `[get_ports clk]` problem. On Path A,
`RUN_CTS false` handles it for you.

### 5.5 🔴 The filler trap — Path B only, but understand it either way

`routing_cp8d.tcl` carries an SCL comment saying a combinational design can read the
**placement** DEF and skip CTS. **Following that as written loses your filler cells:**

- `placement_cp8d.tcl` ends at `detailed_placement` + `check_placement` — **no**
  `filler_placement`.
- `cts_cp8d.tcl` is the **only** stock script that calls it.

**CP8D ships no tap/welltap cell.** At 0.8 µm the well and substrate contacts are drawn
inside every standard cell and inside the fillers, so **filler insertion *is* the tap
strategy on this process**. No fillers ⇒ broken nwell/implant continuity ⇒ signoff DRC
failures. On Path A the native filler step covers this via `FP_FILL_CELL`; confirm your
post-fill DEF actually contains `FILLER` instances before signoff.

### 5.6 `CLOCK_PERIOD` never reaches synthesis

`abc -liberty` is called with no `-D` and no SDC, so ABC maps for **area**, not timing.
`CLOCK_PERIOD` only feeds `create_clock` in STA. A full re-run to "get timing-driven
synthesis" buys nothing — re-run STA alone. This also explains why the adder maps to a
gate carry chain rather than `ADR100`.

### 5.7 The floorplan row situation — do not "fix" it

The tech LEF declares a SITE height of **25.35** while the cells are **32.35** tall, so
`initialize_floorplan -site CORE` builds **overlapping rows**. Path B's
`floorplan_cp8d.tcl` works around it by destroying every odd row:

```tcl
foreach row $block { if {[expr $count % 2] != 0} { odb::dbRow_destroy $row }; incr count }
```

25.35 × 2 = **50.70 µm**, exactly the observed row pitch. 18.35 µm of every row is dead
space (36 % wasted) — harmless at ~1 % utilisation, but it means no density figure from
Path B is meaningful.

**`PLACE_SITE_HEIGHT 32.35` is correct — never change it to 25.35.** Un-flipped rows at
25.35 pitch would lay one row's VDD rail across the next row's GROUND rail: a short.

⚠️ **Path A does not do the row deletion.** If the native flow places cleanly at full row
count, that is a genuinely new result and worth telling Deepesh — the open question is
whether the real pitch is 25.35 with alternating N/FS shared rails, or effectively 50.7.
Only the 50.7 version has ever produced a clean DRC + LVS here. **Check it with KLayout
before claiming it works.**

---

## 6. Running Path B (for reference)

```bash
sclenv && olmount
cd /openlane
./flow.tcl -design project_scl_cp8d/alu8 -tag RUN -interactive
```

That gives a **`%` Tcl prompt — not bash.** Then:

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

🔴 **`run_openroad_script` / `run_yosys_script` take a PATH argument** — a bare call fails.

🔴 **`run_openroad_script` prints nothing on success.** Check `results/`, not the terminal.
A dead stage can leave a 0-byte artefact that looks present. **Check sizes, not existence.**

🔴 **`-tag XYZ` is a trap on Path B.** Every `3_src` script hardcodes `runs/RUN` in its
output paths, so `-tag CHIP` creates `runs/CHIP` for bookkeeping while every stage writes
into `runs/RUN` anyway, silently overwriting it. Rename first: `mv runs/RUN runs/RUN_<name>`,
swap `config.json`, run as `-tag RUN`, rename afterwards. **Path A has no such problem —
`-tag` works normally**, which is one reason your `runs/run7` is a sane layout.

⚠️ `-overwrite` deletes all of `runs/RUN`, `.bak` subdirectories included.

---

## 7. Expected results

### 7.1 Path B artefact sizes (W0 reference, 1 mm die) — **not a target for Path A**

| stage | artefact | size |
|---|---|---|
| yosys | `results/synthesis/alu8_sys.v` | 20,959 B — **210 CP8D cells** |
| placement | `results/placement/alu8_pl.def` | 404,259 B (4 mm die) |
| fill | `results/cts/alu8_plcts.def` | 566 components = 210 logic + 356 FILLER |
| routing | `results/routing/alu8_rt.def` | 319,149 B |
| | `results/routing/drc.rpt` | **0 bytes = router DRC pass** |
| rcx | `results/spef/alu8.spef` | 155,176 B |
| sta | `results/sta/timing_report.txt` | setup 11.61 ns, slack +88.39 MET |

`drc.rpt` is the one artefact where **0 bytes means success**.

**The only figure that should transfer to Path A is the cell count: ~210.** Synthesis
never sees the die, the density or the placement, so a materially different cell count on
Path A means your RTL or Yosys invocation differs — worth chasing. Everything downstream
of synthesis legitimately differs between the paths.

⚠️ On Path B, STA writes to `results/sta/`, **not** `reports/`, and `runs/RUN/reports/`
and `logs/` stay empty forever because raw `run_openroad_script` calls bypass OpenLane's
native reporting tree. **Path A populates both properly** — another reason your run is
easier to debug.

### 7.2 The three caveats that must travel with every number — both paths

1. 🔴 **"≈86 MHz" is cell delay only.** The SCL PDK's RCX rule deck has no resistance
   model and CP8D no capacitance model, so the SPEF is connectivity-only with every
   `*D_NET` capacitance = 0. This is **measured**, not assumed: the timing report here is
   byte-identical across a 1 mm and a 4 mm die (16× area, ~40× wire length) and across
   three placement densities. Never present it as post-layout signoff timing.
2. **Typical corner only** — 5 V / 25 °C. CP8D ships no worst-case library.
3. 🔴 **Router DRC ≠ signoff DRC.** A 0-byte `drc.rpt` means the router's own check passed
   against the **LEF abstract, which has no poly**. Signoff flattens the real GDS. On this
   design, router DRC was clean while KLayout signoff found real violations. **Never write
   "DRC clean" without the word *router* unless KLayout says so.**

A reproduced example of (3): at low placement density, nets run long distances *across*
cells and vias land over poly the router cannot see — 6–8 `9.4.1` via-to-poly violations
with a clean `drc.rpt`. Both statements are true; they describe different views.

⚠️ **A KLayout item count is not a defect count.** An 8-item report here was 5 real vias —
three flagged twice, once per edge of the same via, separated by exactly the via width.
Parse the edge-pairs before quoting a number.

---

## 8. Verification checklist

### 8.1 Environment — both paths

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

### 8.2 Flow — Path A

1. `./flow.tcl` completes **through routing** without a `kill signal`.
2. Synthesis reports **~210 CP8D cells** (see §7.1 — this is the one cross-path number).
3. Your post-fill DEF contains `FILLER` instances (§5.5).
4. KLayout DRC + LVS run to completion on the GDS, with `<original-file>` and
   `<generator>` verified in the report header.

**Do not** check your artefact byte sizes against §7.1 — those are Path B numbers and a
correct Path A run will not match them.

### 8.3 Flow — Path B

`runs/RUN/results/routing/alu8_rt.def` == **319,149 bytes** and `drc.rpt` == **0 bytes**.
The flow is deterministic: a re-run with identical inputs reproduces these byte-for-byte,
through signoff. Different sizes ⇒ an input differs; find it before interpreting anything.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `child killed: kill signal` in `gpl.tcl` | SIGKILL from outside — OOM killer or WSL2 memory cap | §1.2; `dmesg -T \| grep -i oom`; raise `.wslconfig`; never run two flows at once |
| `Cannot connect to the Docker daemon` | no systemd in WSL | `sudo service docker start`, or enable systemd in `/etc/wsl.conf` |
| `sclenv` prints a `PDK_ROOT` collision warning | Cadence environment in the same shell | dedicated terminal; never source `cadence.bash` here |
| `$PDK_ROOT` expands to `//` | you `source`d `sclenv` instead of running it | run `sclenv` as a command |
| `[get_ports clk]` error in STA or CTS | combinational design, no clock port | §5.4; `RUN_CTS false` |
| Signoff DRC fails on well/implant continuity | fillers missing | §5.5 — verify `FILLER` instances exist |
| Placement overlap / row errors | the 25.35 vs 32.35 SITE mismatch | §5.7 — do **not** set `PLACE_SITE_HEIGHT` to 25.35 |
| A stage "succeeded" but the next fails | Path B prints nothing on success; a dead stage leaves a 0-byte file | check artefact **sizes** after every stage |
| `runs/XYZ` empty after `-tag XYZ` | Path B scripts hardcode `runs/RUN` | §6, rename-first procedure |
| KLayout report shows the wrong design | report header lies, or CWD-relative output clobbered | read `<original-file>` / `<top-cell>` / `<generator>` first |
| `FOREIGN name SPAD00 differs from MACRO ASPAD00` | known SCL bug in `pads_cp8d.lef` | benign, ignore |
| LVS banner says "SCL C1D runset" while running CP8D | stale header copied from the 1.2 µm kit | benign — it is the right deck |
| `PDK 'scl_cp8d' ... will generate errors with instantiated stdcells` | synthesis-stage linter warning | benign on its own; see §1.2 — it is not why a run dies at Step 6 |
| Everything is glacially slow | tree on `/mnt/c/` | §1.4, move to `~/` |

---

## 10. What never goes into a git repository

Before any `git add`, in **your** repo or any other:

- `*.lib`, `*.lef` (`tech_cp8d.lef`, `core_cp8d.lef`, `pads_cp8d.lef`, `corner_cp8d.lef`)
- `*.lydrc`, `*.lylvs`, `*.tech`, any cell GDS, `core_iolib_cp8d.cdl`
- the PDK zip or any part of the kit tree
- **`runs/*/tmp/`** — carries `merged.*.lef` and several `*.lib` ≈ **14.5 MB of PDK per
  run tree**. This is the realistic accident; it is easy to miss in an `rsync`.

⚠️ `rsync --exclude='*.bak'` matches the **directory** `RUN.bak/` too, silently skipping
your failure-evidence tree. Use explicit paths instead.

**Fine to commit:** flow scripts, `config.json`, `pin_order.cfg`, and all run outputs —
netlist, DEFs, SPEF, SDF, STA reports, `drc.rpt`. They describe the design and the flow,
not the PDK. Cell *names* appearing in a netlist are not PDK data.

---

## 11. Process note

CP8D is **0.8 µm = 800 nm**, a ~1990s node — an educational/open kit with **two metal
layers**. That is why vertical metal2 power stripes stay commented out in `pdn_cp8d.tcl`:
with only two layers, power and signal compete for the same tracks, whereas in a 6–10
metal process you strap on upper layers and never notice. Worth being able to explain.

---

*Companion documents in this repo:* `docs/flow-notes.md` (the combinational-on-CP8D
technique in full), `docs/engineering-notes.md` (status, open items, corrections),
`docs/signoff.md` (KLayout DRC/LVS), `docs/determinism.md` (re-run evidence),
`docs/failed-runs.md` (how to read the error logs in `runs/`).
