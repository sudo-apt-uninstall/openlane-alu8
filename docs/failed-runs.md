# Run trees: what each one is

Three run trees are preserved under `runs/`. They are **two separate executions
of the same flow plus one aborted attempt** — kept because a tree that only ever
shows success teaches nothing, and because the pair of completed runs is what
proves the flow is deterministic.

| tree | what it is | entry point | reached STA? |
|---|---|---|---|
| `RUN` | the **2026-10-22 scripted re-run**, driven by `flow/run_all.tcl` | `flow.tcl -interactive` | yes |
| `RUN_COMPLETE_20261021` | the **original 2026-10-21 run**, executed stage by stage by hand | raw `run_openroad_script` | yes |
| `RUN.bak` | aborted attempt, 02:15, run-tag collision | `flow.tcl` | no |

`tmp/`, `*.odb` and all PDK files are excluded from every tree. `tmp/` in
particular holds `merged.{nom,min,max}.lef` and `merged` / `trimmed` / `cts*.lib`
copied out of the SCL CP8D PDK; those are not redistributed here.

> ⚠️ **This page previously described `RUN` and `RUN_COMPLETE_20261021` as the
> same run captured twice, differing only in `cmds.log`.** That was accurate when
> written. It is no longer: `flow.tcl -overwrite` deleted the original `RUN` and
> the 2026-10-22 re-run took its place. The description below is current.

## The two completed trees — and why having both matters

They are **different executions**, and their top-level files differ accordingly:

| file | `RUN` (re-run) | `RUN_COMPLETE_20261021` (original) |
|---|---:|---:|
| `config.tcl` | 18,232 B | 83 B |
| `cmds.log` | 8,011 B | 8,593 B |
| `openlane.log` | 188 B | 1,661 B |
| `errors.log` | **absent** | 1,435 B |

The `config.tcl` difference is the entry point, not the stages. Launching through
`flow.tcl -interactive` expands the full configuration into the run directory;
the original session invoked the stages directly and left an 83-byte stub. In
**both** trees the stages themselves were raw `run_openroad_script` calls, which
is why `reports/` and `logs/` are empty in both.

`RUN` has **no `errors.log` at all** — the scripted re-run produced no errors.

**Their `results/` are byte-identical.** Same inputs, same tool, same outputs,
across two independent executions days apart. Anyone cloning this repository can
check that claim rather than take it:

```bash
diff -rq runs/RUN/results runs/RUN_COMPLETE_20261021/results
```

See [`determinism.md`](determinism.md) for the artefact-size table.

## `RUN.bak` — run-tag collision, not a design failure

`errors.log` (121 B) in full:

    [ERROR]: A run for alu8 with tag 'RUN' already exists. Pass the -overwrite
    option to overwrite it or use a different tag

`openlane.log` (453 B) shows how far it got: it set the run directory, saved the
runtime environment, prepared LEF files for the nom, min and max corners, then
re-entered the run directory and aborted. Nothing in the design was wrong. The
flow refused to clobber an existing `RUN` tag.

Its `results/` holds only two stages, both byte-size-identical to the completed
runs: `synthesis/alu8_sys.v` 20,959 B and `floorplan/alu8.def` 24,648 B.

**Lesson:** pass `-overwrite`, or pick a new tag, before re-invoking the flow.

## The rcx failure — preserved in `RUN_COMPLETE_20261021/errors.log`

That file is 1,435 B and records:

    ERROR (DEFPARS-6002): Incomplete def file. Error in file
    .../runs/RUN/results/routing/alu8_rt.def at line 1, on token <unprintable>.
    [ERROR ODB-0421] DEF parser returns an error!

It is **superseded, and it is not an rcx bug.** A dead routing invocation left a
zero-byte `alu8_rt.def`; `rcx_cp8d.tcl` then correctly refused to parse it. The
script is innocent — the input was empty. Re-running routing fixed it, and rcx
then completed. The routed DEF now in `results/routing/alu8_rt.def` is
319,149 B, router DRC came back clean (`drc.rpt`, 0 bytes), and STA finished.

**Lesson — and it is the reason `run_all.tcl` exists in its current form:** check
artefact *sizes*, not merely that a file exists. A 0-byte output is
indistinguishable from a real one in `ls` without `-l`, and it propagates
silently into the next stage. `run_all.tcl` now asserts a non-empty artefact
after every stage, so this failure mode stops the flow immediately instead of
surfacing two stages later as someone else's error message.

## Empty by design, not by omission

`reports/` and `logs/` are empty in both completed trees and always were: the
stages were run as raw `run_openroad_script` calls, which bypass OpenLane's
native reporting tree. STA output is written to `results/sta/`, not `reports/`.
Git does not track empty directories, so these do not appear in the repository
at all.
