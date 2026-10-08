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

up to 4 series, up to 8192 points; colorIdx 0..3 = matplotlib
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

one bar series: up to 4 of them, up to 8192 bars each, drawn
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

### Viridis () : Cmap

_(documented with the group below)_

### Coolwarm () : Cmap

_(documented with the group below)_

### CmapHex (cmap: Cmap ; t: F64) : STR RAISES ValueRange

the colour at t in 0 .. 1 of a colour map, as '#rrggbb' -- what
RenderHeat fills a cell with, for a figure drawn elsewhere
(Map's colour grid, 2026-10-08); t is clamped to 0 .. 1

### SetLineColor (series: I64 ; RO KEPT hex: STR)

the line twin of SetBarColor: override one line series' palette
entry with an SVG colour -- 'black', '#cc3311'.  Written into
the document verbatim, so it is the caller's business that it is
a colour; an empty string restores the C0..C3 entry.  Added
because the palette has no black and a measured series wants
one (Alex, 2026-09-01).

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

### Render (RO title: STR ; RO xlabel: STR ; RO ylabel: STR) : STR RAISES ValueRange

_(undocumented)_

### RenderHeat (RO title: STR ; m: PTR Mat.Matrix ; cmap: Cmap ; symmetric: BOOL) : STR RAISES ValueRange

symmetric centres the scale on zero, for anomaly fields;
NaN cells render white

### SetHeatRange (lo: F64 ; hi: F64)

pin the next RenderHeat's colour range to [lo, hi], overriding
both the data min/max and symmetric; ClearFigure clears it.  For
a rounded, stable scale that a caller controls.

### CONST TaylorMax

the outer arc: a larger ratio is not on
the diagram

### TaylorXY (ratio, corr: F64 ; VAR x, y: F64) : BOOL RAISES ValueRange

where RenderTaylor puts a point, in the units of its 720 by 720
drawing (y downwards, as SVG counts).  FALSE, and x and y left
alone, for a point that is not on the diagram: a NaN, a
correlation outside 0 .. 1, a ratio below 0 or above TaylorMax.
Exported so that the geometry can be held to a number: the
distance to TaylorXY (1, 1), divided by the distance from
TaylorXY (0, 1) to it, is the RMS difference.

### RenderTaylor (RO title: STR ; RO ratio: GRID 2 OF F64 ; RO corr: GRID 2 OF F64 ; RO cases: SLICE OF STR ; RO names: SLICE OF STR) : STR RAISES ValueRange, Faults.SizeError

the diagram as SVG.

  ratio, corr -- one ROW a case, one COLUMN a variable
  cases       -- a name per row, for the legend; each case has
                 a colour (red, blue, then four more, then round
                 again)
  names       -- a name per column, listed at the left as
                 `3 - Prc_GPCP`; the point carries the number

A point TaylorXY refuses is not drawn, and the figure says how
many were not.  SizeError (got, want) when the two grids differ
in shape or the names do not count their rows and columns.

### CONST ChartSlots

station slots s1 .. s6

### TYPE Trace

the legend's text

### TYPE ChartSpec

pixels

### Chart (RO s: ChartSpec) : STR RAISES ValueRange

the document.  A spec with nothing in its window still answers
a figure: the axes, and a line saying there is no data.

### MonthName (m: I64) : STR

'Jan' .. 'Dec' for 1 .. 12

### Panels (cols, rows: I64 ; RO figures: SLICE OF STR ; RO title: STR ; width, height: I64) : STR RAISES Faults.SizeError, Faults.BadArg, ValueRange

the document, width by height points, `title` across the top
when it is not empty.  The figures fill the cells row by row,
from the top left; fewer than cols * rows leaves the last cells
empty, more is Faults.SizeError (got, want).  A figure must
begin with <svg and say its size in a viewBox (every figure
of this module does); Faults.BadArg otherwise, and for a grid
or a size that is not positive.

### FmtG (dst: C.MutPtr ; v: C.Double) : C.Int [REENTRANT]

sprintf "%.4g" -- the oracle's exact formatter, shared
