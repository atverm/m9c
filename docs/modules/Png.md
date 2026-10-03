# Png

PNG files, written in M9 (2026-10-02; Alex: "encoder for
rasterizing svg to png").  This is the ENCODER: pixels in, the
bytes of a .png file out.  Eight bits a channel, red green blue,
no transparency and no palette -- what a figure on white paper is.

The image data is compressed by Zip.Compress, which is a plain
deflate: a file from here is two to four times the size an
optimising PNG writer makes of the same picture, and every PNG
reader reads it.

Held by corpus/PngTest.m9, which reads its own files back through
Zip.Decompress, and by runtime/test/deflate.sh, where Python does:
every chunk's CRC, the header's fields, and each pixel.

### Encode (VAR pool: POOL ; RO rgb: SLICE OF BYTE ; width, height: I64 ; dpi: F64) : SLICE OF BYTE RAISES Faults.SizeError, Faults.BadArg, ValueRange

the file for an image of width by height pixels.

  rgb -- three bytes a pixel, red green blue, the rows from the
         TOP down and each from the left: 3 * width * height of
         them (Faults.SizeError otherwise)
  dpi -- the resolution the picture is meant at, written into
         the file (a pHYs chunk) so that a program placing it
         gives it its size on paper; 0.0 writes none

Faults.BadArg for a width or a height that is not positive, and
for a dpi that is negative or not a number.

### EXCEPTION Error

a PNG file Decode cannot read: not a PNG, a chunk's CRC wrong,
a kind of image this does not read (interlaced, palette, 16-bit)

### FromSvg (VAR pool: POOL ; RO svg: STR ; dpi: F64) : SLICE OF BYTE RAISES Faults.SizeError, Faults.BadArg, ValueRange

the figure as a PNG file at dpi dots an inch, which is written
into the file too

### Raster (VAR pool: POOL ; RO svg: STR ; dpi: F64 ; VAR width, height: I64) : SLICE OF BYTE RAISES Faults.BadArg, ValueRange

the same as pixels, three bytes each, rows from the top: what
Encode takes, for a caller that draws on or compares them

### Decode (VAR pool: POOL ; RO file: SLICE OF BYTE ; VAR width, height: I64) : SLICE OF BYTE RAISES Error, Zip.Error, ValueRange

a PNG file's pixels, as Raster answers them: 8-bit RGB or RGBA
(transparency laid on white), not interlaced -- what Encode and
a browser's screenshot write.  For a test that compares two
pictures, and for a program that reads one back.
