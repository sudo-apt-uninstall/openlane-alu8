# Router DRC result

`drc.rpt` in this directory is **0 bytes**. That is the result, not a missing file.

OpenROAD's detailed router writes one line per violation. An empty report means
**zero DRC violations** on the routed design (2 metal layers, SCL CP8D 0.8 um).

Caveat: this is *router* DRC. Signoff DRC/LVS in KLayout against the PDK rule
deck is a separate check and has not been run on alu8 (it was clean on cnt8).
