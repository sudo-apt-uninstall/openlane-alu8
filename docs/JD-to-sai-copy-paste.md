## Conclusion

You'll run classic OpenLane (The‑OpenROAD‑Project/OpenLane, tag **2023.09.07** — I confirmed this tag exists directly on GitHub, and it's the exact version SCL's own 114‑page CP8D digital reference doc specifies in Table 5, not the generic "1.0.X" string in the kit's quick‑start file) inside **WSL2 Ubuntu 22.04**, driven by **Docker** (Desktop or native), with the `scl_cp8d` PDK mounted via `make mount`. **KLayout must be exactly version 0.30.5** (apt's own Ubuntu 22.04 package is only 0.26.2 — confirmed via packages.ubuntu.com/pkgs.org against KLayout's own release page) for DRC/LVS signoff, and its GUI needs **WSLg** (automatic on Windows 11) or an X server (Windows 10). Everything below is SCL's own procedure from `sudo-apt-uninstall/SCL_0.8-um-PDK → SCL_CP8D_PDK_v1/digital_cp8d/Readme_0.8u_digital.txt`, `Installation_guide_cp8d.txt`, and `.../project_scl_cp8d/cp8d_pdk_env_setting.source`, mapped onto WSL.

---

### Stage 0 — Pick your GUI path
- **Windows 11** (build 22000+): WSLg ships built in. KLayout/OpenROAD GUI windows just appear. Skip Stage 3.
- **Windows 10**: no WSLg — you need an X server (VcXsrv or X410) on the Windows side. Do Stage 3.

### Stage 1 — Install WSL2 + Ubuntu 22.04
PowerShell (Admin):
```
wsl --install -d Ubuntu-22.04
```
Reboot if asked, set a UNIX user/password on first launch, then confirm:
```
wsl -l -v          # must show Ubuntu-22.04 … VERSION 2
sudo apt update && sudo apt -y upgrade
```

### Stage 2 — Docker
**Option A (has admin rights to install software):** install Docker Desktop → Settings → General → "Use the WSL 2 based engine" → Settings → Resources → WSL Integration → toggle ON for Ubuntu‑22.04. Verify from inside WSL: `docker version` then `docker run hello-world`.
**Option B (no admin for new software, only WSL feature already enabled):** install `docker-ce` natively inside the Ubuntu instance via Docker's own apt repo for Ubuntu 22.04 (`docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`). WSL2 doesn't auto-run systemd by default on older installs — either add `[boot]\nsystemd=true` to `/etc/wsl.conf` and `wsl --shutdown`/reopen, or run `sudo service docker start` in every new terminal.

### Stage 3 — GUI passthrough (Windows 10 only)
Install VcXsrv, launch with "Disable access control" and "Multiple windows" checked, allow it through Windows Defender Firewall on the private network, then in WSL:
```
echo 'export DISPLAY=$(ip route list default | awk "{print \$3}"):0' >> ~/.bashrc
echo 'export LIBGL_ALWAYS_INDIRECT=1' >> ~/.bashrc
source ~/.bashrc
sudo apt install -y x11-apps && xeyes   # sanity check
```

### Stage 4 — Base packages
```
sudo apt install -y git make python3 python3-pip python3-venv iverilog gtkwave unzip curl
```

### Stage 5 — Install OpenLane at the CP8D-validated tag
```
cd ~
git clone https://github.com/The-OpenROAD-Project/OpenLane.git
cd OpenLane
git checkout 2023.09.07
make            # one-time: pulls/builds the OpenLane docker image, several GB, needs internet
```
Note on the version mismatch I found: SCL's quick‑start header (`Readme_0.8u_digital.txt`) says "OpenLane 1.0.X" — that's leftover C1D‑kit wording. The 114‑page CP8D reference doc's own Table 5 is precise: **OpenLane 2023.09.07, Icarus Verilog 11.0, KLayout 0.30.5, Ubuntu 22.04.5** — no separate Yosys version listed (it ships bundled in the OpenLane image). Use `2023.09.07`.

### Stage 6 — Get your own PDK onto the Linux filesystem (not `/mnt/c`)
It's your private repo, so clone it with your own GitHub auth (PAT or `gh auth login`):
```
cd ~
git clone https://github.com/sudo-apt-uninstall/SCL_0.8-um-PDK.git scl-pdk-src
mkdir -p ~/my_dtech_cp8d
unzip ~/scl-pdk-src/SCL_CP8D_PDK_v1/digital_cp8d/my_dtech_cp8d.zip -d ~/my_dtech_cp8d
```
This reproduces exactly the verified path `~/my_dtech_cp8d/Open_Source_SCL_0.8micron_PDK_digital/open_source_scl_cp8d/open_pdks/scl_cp8d/...` that the kit's scripts expect.

### Stage 7 — PDK integration into OpenLane (per the kit's own §A)
```
cp -r ~/my_dtech_cp8d/Open_Source_SCL_0.8micron_PDK_digital/open_source_scl_cp8d/open_pdks/scl_cp8d/libs.ref/digital_cp8d/project_scl_cp8d ~/OpenLane/designs/
```
If either folder isn't in `~`, edit only the `MY_DTECH_DIR_PATH` and `OPENLANE_PATH` lines in the copied `project_scl_cp8d/cp8d_pdk_env_setting.source` — `PDK_ROOT`, `PDK`, `KLAYOUT_PATH` derive from those two and the file itself says not to touch them.

### Stage 8 — Create and configure a project
```
cd ~/OpenLane/designs/project_scl_cp8d
cp -r sample_project_files_cp8d project1
cd project1
```
Drop your RTL `.v` into `1_RTL/`; edit `config.json` (`DESIGN_NAME`, `DESIGN_TOP_CELL_NAME`, `DIE_AREA`, `CORE_AREA`, `CLOCK_PERIOD`, `CLOCK_PORT`, `PL_TARGET_DENSITY`, `FP_PIN_ORDER_CFG`, `FP_PDN_SKIPTRIM`) and `pin_order.cfg`. **Edit these only with a WSL-native editor** (`nano`/`vim`, or VS Code's "Remote – WSL" extension) — Windows Notepad can inject CRLF line endings that break the Tcl/JSON silently.

### Stage 9 — Source the environment (repeat every new terminal)
```
cd ~/OpenLane/designs/project_scl_cp8d
source cp8d_pdk_env_setting.source
```
Check the printed `HOME / MY_DTECH_DIR / PDK_ROOT / PDK / OPENLANE_PATH` are correct.

### Stage 10 — RTL prelayout simulation (Icarus)
Put your testbench in `2_iverilog_prelayout/tb_prelay_sim/`, edit `tb_prelay_script.source`'s name variables, then:
```
cd ~/OpenLane/designs/project_scl_cp8d/project1/2_iverilog_prelayout/tb_prelay_sim
source tb_prelay_script.source
```

### Stage 11 — Run the OpenLane RTL‑to‑DEF flow
```
cd ~/OpenLane/designs/project_scl_cp8d && source cp8d_pdk_env_setting.source
cd ~/OpenLane
make mount PDK_ROOT=$MY_DTECH_DIR_PATH/Open_Source_SCL_0.8micron_PDK_digital/open_source_scl_cp8d/open_pdks PDK=scl_cp8d
```
Inside the container:
```
./flow.tcl -design project_scl_cp8d/project1 -tag RUN -interactive
run_yosys_script $::env(DESIGN_DIR)/3_src/yosys_script.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/floorplan_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/pdn_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/placement_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/cts_cp8d.tcl   # skip for pure-combinational/ring-osc designs; run filler_placement.tcl instead
run_openroad_script $::env(DESIGN_DIR)/3_src/routing_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/rcx_cp8d.tcl
run_openroad_script $::env(DESIGN_DIR)/3_src/run_sta.tcl
exit
exit
```
Or the batch shortcut: `source $::env(DESIGN_DIR)/3_src/script_openlane.tcl`. If placement/routing fails, tune `PL_TARGET_DENSITY`/`DIE_AREA`/`CORE_AREA` and rerun `./flow.tcl ... -overwrite` (wipes the RUN folder — back it up first).

### Stage 12 — DEF→GDS, DRC, LVS in KLayout
Don't use `apt install klayout` — Ubuntu 22.04's own package is 0.26.2, far behind SCL's validated 0.30.5. Get the matching Ubuntu‑22 `.deb` from klayout.de's build/download page (klayout.de/build.html → "Ubuntu 22" → pick the 0.30.5 entry in that platform's version archive), then:
```
sudo apt install -y ./klayout_0.30.5-*_amd64.deb
klayout -v        # confirm 0.30.5
```
Then:
```
cd ~/OpenLane/designs/project_scl_cp8d/project1/5_klayout
# edit cdl_gds_script.source: PROJECT_NAME / DESIGN_NAME / DESIGN_TOP_CELL_NAME
source cdl_gds_script.source
```
In KLayout: **View → Grid → 5nm**; confirm the tech dropdown shows **scl_cp8d**; run **Tools → DRC** against `<PDK_ROOT>/scl_cp8d/libs.tech/klayout/tech/drc/drc.lydrc`; run **Tools → LVS** against `.../libs.tech/klayout/tech/lvs/lvs.lylvs`. Reports land in `5_klayout/lvs_drc/`. Any residual DRC hit gets fixed by hand per Annexure‑1 of the 114‑page reference doc.

### Stage 13 — Post-layout sim and standalone GUI tools
Copy `.v`/`_tb.v` into `6_iverilog_postlayout/tb_postlay_sim/`, add `$sdf_annotate("…/runs/RUN/results/sta/<design>.sdf", uut);` to the testbench, edit `tb_postlay_script.source`, run it, view in GTKWave. Standalone KLayout: `source cp8d_pdk_env_setting.source && klayout -e&`. OpenROAD GUI: re-enter with the same `make mount …`, then `openroad` → `gui::show`.

### WSL-specific pitfalls (not in SCL's doc — learned from the platform, not the kit)
1. Keep everything under `~` (WSL's ext4 disk), never `/mnt/c/...` — Docker bind mounts and KLayout I/O across the 9p bridge to NTFS are much slower and can fail silently. Biggest WSL-specific gotcha.
2. Docker Desktop: confirm WSL Integration is ticked for the exact Ubuntu‑22.04 distro, or `docker` inside WSL won't see the daemon.
3. Native `docker-ce` without systemd doesn't auto-start — script `sudo service docker start` into `.bashrc` or enable systemd in `/etc/wsl.conf`.
4. Any `.source`/`.tcl`/`.cfg`/`.json` file touched from a Windows editor must stay pure LF — CRLF breaks these scripts with a cryptic `$'\r': command not found`.
5. `make` (image pull) needs real bandwidth the first time; do it once, not per-project.
6. If a Wipro-managed laptop blocks installing Docker Desktop, native `docker-ce` inside WSL is the fallback — it only needs admin once, to enable the WSL feature itself.

Sources used: `sudo-apt-uninstall/SCL_0.8-um-PDK` → `SCL_CP8D_PDK_v1/digital_cp8d/Readme_0.8u_digital.txt`, `Installation_guide_cp8d.txt`, `.../project_scl_cp8d/cp8d_pdk_env_setting.source` (private, read per the standing PDK whitelist rule — use freely, don't redistribute); `sudo-apt-uninstall/artifacts-3/scl/README.md` for the OpenLane‑version cross-check; GitHub tag list for `The-OpenROAD-Project/OpenLane` (public, read directly); web search for KLayout's apt-vs-upstream version gap.

Now logging this exchange verbatim to the RFAST log repo.

Logged successfully to `sudo-apt-uninstall/wi26-vx01-008-rfast-log` → `exchanges/2026-10-27/213305-rfast.md`.

---

The guide above (OpenLane tag `2023.09.07` + WSL2 Ubuntu 22.04 + Docker + KLayout 0.30.5) is the complete setup/run procedure, sourced directly from your `SCL_0.8-um-PDK` repo's `Readme_0.8u_digital.txt`, `Installation_guide_cp8d.txt`, and `cp8d_pdk_env_setting.source`, with WSL-specific adaptations and the OpenLane-tag/KLayout-version discrepancies cross-checked against GitHub and the web. One open item I didn't chase down: whether a Wipro-managed laptop will actually permit enabling the WSL2/Virtual Machine Platform Windows features or installing Docker Desktop — that's a policy question only you can answer by trying `wsl --install`, and Stage 2's "Option B" is the fallback if Docker Desktop itself is blocked.
