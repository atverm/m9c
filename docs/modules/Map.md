# Map

A world map as one SVG document: coastlines and a graticule in a
projection the caller names, a backdrop already in that projection
(NASA's Blue Marble warped by Warp), a transparent colour grid of
values on a longitude-latitude grid -- an atmospheric footprint --
in Plot's viridis between the map and the markers, and markers
with labels on top.  A window zooms; the default is the globe.

Lifted from m9curve's Map.m9 and NatEarth.m9 (2026-10-08), where
the window and the projection were fixed: here the projection is a
PROCEDURE VALUE (par 2.2.3), so another projection is a procedure
the caller writes, and the window is a record.  Natural Earth
(Savric, Jenny, Patterson, Petrovic and Hurni, 2011) and the plate
carree are supplied.

The document styles every element by attributes, no CSS, as
Plot.Chart does.  It is a figure for a browser or a page: the
backdrop is an <image>, which Png.FromSvg does not draw.

### TYPE Projection

degrees in, the longitude RELATIVE to the centre meridian, in
-180 .. 180; unit-sphere coordinates out, x east and y north

### TYPE Unprojection

the way back, for Warp: a point outside the globe answers a
latitude beyond 90 degrees

### TYPE Window

degrees; Globe () is -180, 180, -90, 90.  In the projection the
window is what its four edges project to, which is not a
rectangle.  A window of the whole round, 360 degrees of
longitude, is bounded by the map's own cut -- the meridians 180
degrees from the centre -- whatever longitudes it names; a
narrower window across that cut (west past east) is drawn in two
pieces, so give it a centre meridian of its own.

### TYPE Backdrop

the image; '' draws none

### TYPE Marker

an SVG colour; '' is the default

### TYPE Scale

base 10; values <= 0 are left out

### TYPE Spec

the centre meridian, degrees east

### NaturalEarth (lon: F64 ; lat: F64 ; VAR x: F64 ; VAR y: F64)

the Natural Earth projection of the unit sphere: parallels
straight, meridians curved, the pole a line

### NaturalEarthInverse (x: F64 ; y: F64 ; VAR lon: F64 ; VAR lat: F64)

Newton on y for the latitude, eight steps, then the longitude
from x; a y beyond the poles answers a latitude beyond 90

### PlateCarree (lon: F64 ; lat: F64 ; VAR x: F64 ; VAR y: F64)

_(documented with the group below)_

### PlateCarreeInverse (x: F64 ; y: F64 ; VAR lon: F64 ; VAR lat: F64)

degrees as radians: x = lon, y = lat on the unit sphere

### Globe () : Window

_(documented with the group below)_

### Default () : Spec

Natural Earth about Greenwich, the globe, 960 pixels wide, a
graticule every 30 degrees, coastlines, a logarithmic scale
between the 1st and the 99th percentile at opacity 0.65, no
backdrop, no title, Natural Earth credited

### Range (RO scale: Scale ; RO values: GRID 2 OF F64 ; VAR lo, hi: F64) : BOOL RAISES ValueRange, Faults.BadArg

the colour scale's ends: the low and the high percentile of the
values PRESENT -- finite, and positive when the scale is
logarithmic -- by numpy's linear rule; FALSE, and nothing to
draw, when none is.  A BadArg names a percentile outside 0 .. 100.

### Render (RO spec: Spec ; RO lons: SLICE OF F64 ; RO lats: SLICE OF F64 ; RO values: GRID 2 OF F64 ; RO markers: SLICE OF Marker) : STR RAISES ValueRange, Faults.BadArg, Faults.SizeError

the document.
lons, lats -- the centres of the value grid's cells, ascending;
              a cell reaches halfway to its neighbours.  No
              longitudes is no colour grid.
values     -- values[lat, lon]; a NaN is a cell not drawn.
              SizeError when the shape is not LEN lats by LEN lons.
markers    -- drawn in order, a label beside each; one outside
              the window is left out.
A BadArg names a missing projection, a width of nothing, or
centres that do not ascend.

### Warp (VAR pool: POOL ; RO rgb: SLICE OF BYTE ; w, h: I64 ; unproj: Unprojection ; lon0: F64 ; x0, x1, y0, y1: F64 ; outW, outH: I64) : SLICE OF BYTE RAISES ValueRange, Faults.SizeError

a backdrop: the whole-globe plate carree picture rgb (w by h
pixels, three bytes each, row 0 at 90 N, column 0 at 180 W --
how NASA publishes the Blue Marble) sampled bilinearly into the
projected box x0 .. x1, y0 .. y1 about lon0, outW by outH
pixels; outside the globe black.  Png.Decode reads the source
and Png.Encode writes the answer; the box is the Backdrop's.

### CoastLines () : I64

_(documented with the group below)_

### CoastPoints () : I64

_(documented with the group below)_

### CoastPoint (i: I64 ; VAR lon, lat: F64) RAISES IndexError

the coastline table, Natural Earth 1:110m, for a check against
the file it was cut from
