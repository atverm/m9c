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

### AddLine (RO xs: SLICE OF F64 ; RO ys: SLICE OF F64 ; colorIdx: I64 ; RO KEPT label: STR)

up to 4 series, up to 1024 points; colorIdx 0..3 = matplotlib
C0..C3; NaN values lift the pen, as mpl does.  The label slice
is retained until Render -- ledger material, like AddRoute.

### SetDots (RO KEPT xs: SLICE OF F64 ; RO KEPT ys: SLICE OF F64)

one scatter layer, drawn UNDER the lines: every point a small
black circle, NaN points skipped, no per-series cap -- the
layer is for raw observations behind their summary lines.  The
slices are RETAINED until Render, not copied (the AddLine and
AddRoute precedent), so the caller's arrays must outlive it.
ClearFigure drops the layer with everything else.

### CONST BarVertical

bars rise from the x axis

### CONST BarHorizontal

bars run right from the y axis

### CONST BarGrouped

series side by side in each slot

### CONST BarStacked

series piled on one another

### CONST BarAtValue

a bar is CENTRED on its position

### CONST BarDiscrete

positions ignored: slots 0, 1, 2

### AddBars (RO at: SLICE OF F64 ; RO v: SLICE OF F64 ; colorIdx: I64 ; RO KEPT label: STR)

one bar series: up to 4 of them, up to 1024 bars each, drawn
UNDER any lines and dots.

  at -- where each bar sits on the CATEGORY axis (x for vertical
        bars, y for horizontal ones).  With BarDiscrete the
        values are ignored and the bars take slots 0, 1, 2 ...
  v  -- the bar's length on the VALUE axis.  Negative is legal
        and draws the other way from the baseline; NaN skips
        the bar, as it lifts the pen in AddLine.

Bars and lines can share a figure: the ranges cover both, and a
bar series always includes its baseline so a bar is never drawn
hanging in the air.  colorIdx is the C0..C3 palette, unless
SetBarColor names something else.

### SetBarStyle (dir: I64 ; mode: I64 ; place: I64 ; filled: BOOL ; width: F64)

how every bar series is drawn.  The defaults are what a caller
who never calls this gets: vertical, grouped, at its value,
filled, width 0.8.

  dir   -- BarVertical or BarHorizontal
  mode  -- BarGrouped or BarStacked.  Stacking sums the series
           in the order they were added; a stack of one is a
           plain bar, so grouped and stacked agree for one
           series and that is the check the gate makes.
  place -- BarAtValue centres each bar on its own position and
           sizes the slot from the CLOSEST pair of positions,
           so an irregular axis does not overlap; BarDiscrete
           puts them at 0, 1, 2 ... which is what a category
           chart wants and what the reader means by "bar 3".
  width -- the fraction of a slot the bars occupy, 0 < width
           <= 1.  Grouped series divide that between them.

### SetBarErrors (series: I64 ; RO KEPT err: SLICE OF F64)

symmetric error bars for one series: a whisker of +/- err[i]
on the VALUE axis with a cap at each end, drawn over the bars.
A NaN or negative entry draws nothing for that bar, which is
how "no uncertainty for this one" is said.  The slice is
RETAINED until Render, like AddLine's label and SetDots's
points.

### SetBarColor (series: I64 ; RO KEPT hex: STR)

override the palette for one series with an SVG colour --
'#cc3311', 'darkgreen'.  It is written into the document
verbatim, so it is the caller's business that it is a colour;
an empty string restores the palette entry.

### SetLogX (on: BOOL)

_(documented with the group below)_

### SetLogY (on: BOOL)

a base-10 logarithmic axis, for lines, dots and bars alike.
Ticks land on the decades rather than on NiceStep's round
numbers, and are labelled as the values themselves (100, not
10^2), which is what a reader of a small chart wants.

A value that cannot be shown on a log axis -- zero or negative
-- is SKIPPED, the same treatment NaN gets, rather than clamped
to something that would draw a line to a place the data does
not go.  A bar on a log value axis starts at the axis floor
instead of at zero, because zero is not on the axis.

ClearFigure turns both off again: a second figure in the same
program starts linear, like it starts empty.

### Render (VAR pool: POOL ; RO title: STR ; RO xlabel: STR ; RO ylabel: STR) : STR RAISES ValueRange

_(undocumented)_

### RenderHeat (VAR pool: POOL ; RO title: STR ; m: PTR Mat.Matrix ; cmap: Cmap ; symmetric: BOOL) : STR RAISES ValueRange

symmetric centres the scale on zero, for anomaly fields;
NaN cells render white

### FmtG (dst: C.MutPtr ; v: C.Double) : C.Int [REENTRANT]

sprintf "%.4g" -- the oracle's exact formatter, shared
