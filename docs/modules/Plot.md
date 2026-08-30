# Plot

matplotlib-styled SVG plots, restated from the M2 stack's Plot.mod.
STATEFUL is the definition telling the truth: the line figure is a
module-level builder (ClearFigure / AddLine / Render), exactly the
hidden state the M2 version kept without saying so.  Number
formatting goes through the SAME fmt_g C shim the oracle used, so
the emitted digits are identical by construction, not by hope.
Render answers the SVG as a slice; writing files is the caller's
business (M9 has no file module yet, and the OpenApi precedent
says a document is a value).

### TYPE Cmap

_(undocumented)_

### ClearFigure ()

discards every series added so far and starts an empty figure.

This module is STATEFUL -- the figure being built IS module
state, and the definition says so -- so a second plot in the
same program must start with this call or it inherits the
first one's lines.  One figure at a time is the price of the
state, and the alternative is a figure handle nobody asked
for.

### AddLine (RO xs: SLICE OF F64 ; RO ys: SLICE OF F64 ; colorIdx: I64 ; RO label: STR)

up to 4 series, up to 1024 points; colorIdx 0..3 = matplotlib
C0..C3; NaN values lift the pen, as mpl does.  The label slice
is retained until Render -- ledger material, like AddRoute.

### SetDots (RO xs: SLICE OF F64 ; RO ys: SLICE OF F64)

one scatter layer, drawn UNDER the lines: every point a small
black circle, NaN points skipped, no per-series cap -- the
layer is for raw observations behind their summary lines.  The
slices are RETAINED until Render, not copied (the AddLine and
AddRoute precedent), so the caller's arrays must outlive it.
ClearFigure drops the layer with everything else.

### Render (VAR pool: POOL ; RO title: STR ; RO xlabel: STR ; RO ylabel: STR) : STR RAISES ValueRange

_(undocumented)_

### RenderHeat (VAR pool: POOL ; RO title: STR ; m: PTR Mat.Matrix ; cmap: Cmap ; symmetric: BOOL) : STR RAISES ValueRange

symmetric centres the scale on zero, for anomaly fields;
NaN cells render white

### FmtG (dst: C.MutPtr ; v: C.Double) : C.Int [REENTRANT]

sprintf "%.4g" -- the oracle's exact formatter, shared
