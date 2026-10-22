# Run trees: what each one is

Three run trees are preserved under `runs/`. Only one is a completed flow.
The other two are kept because they document real failure modes, and because
a tree that only ever shows success teaches nothing.

| tree | what it is | reached STA? |
|---|---|---|
| `RUN` | the completed run; all `results/` artefacts come from here | yes |
| `RUN_COMPLETE_20261021` | archived snapshot of the same run (not byte-compared against `RUN`) | yes |
| `RUN.bak` | aborted attempt, 02:15, run-tag collision | no |

`tmp/`, `*.odb` and all PDK files are excluded from every tree. `tmp/` in
particular holds `merged.{nom,min,max}.lef` and `merged` / `trimmed` / `cts*.lib`
copied out of the SCL CP8D PDK; those are not redistributed here.

## `RUN.bak` — run-tag collision, not a design failure

`errors.log` (121 B) in full:

    [ERROR]: A run for alu8 with tag 'RUN' already exists. Pass the -overwrite
    option to overwrite it or use a different tag

`openlane.log` (453 B) shows how far it got: it set the run directory, saved the
runtime environment, prepared LEF files for the nom, min and max corners, then
re-entered the run directory and aborted. Nothing in the design was wrong. The
flow refused to clobber an existing `RUN` tag.

It is a `flow.tcl`-driven tree, which is why it carries the expanded
`config.tcl` (18,232 B) and `config_in.tcl` (1,009 B) that `RUN` does not.

Its `results/` holds only two stages, both byte-size-identical to the final run:
`synthesis/alu8_sys.v` 20,959 B and `floorplan/alu8.def` 24,648 B.

**Lesson:** pass `-overwrite`, or pick a new tag, before re-invoking the flow.

## `RUN/errors.log` is historical — the run did finish

`RUN/errors.log` is 1,435 B and records an rcx failure:

    ERROR (DEFPARS-6002): Incomplete def file. Error in file
    .../runs/RUN/results/routing/alu8_rt.def at line 1, on token <unprintable>.
    [ERROR ODB-0421] DEF parser returns an error!

This is superseded. A dead routing invocation left a zero-byte `alu8_rt.def`;
`rcx_cp8d.tcl` then correctly refused to parse it. The script is innocent — the
input was empty. The routed DEF now in `results/routing/alu8_rt.def` is
319,149 B, router DRC came back clean (`drc.rpt`, 0 bytes), and STA completed.

**Lesson:** check artefact *sizes*, not merely that the file exists. A 0-byte
output looks identical to a real one in `ls` without `-l`.

## Empty by design, not by omission

`RUN/reports/` and `RUN/logs/` are empty and always were: the stages were run as
raw `run_openroad_script` calls, which bypass OpenLane's native reporting tree.
STA output is written to `results/sta/`, not `reports/`. Git does not track empty
directories, so these do not appear in the repository at all.
