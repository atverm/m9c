// mandelbrot in Scala, the same algorithm as Mandel.m9.
//
// Scala is here because it is what the colleagues write: the JVM is
// where a lot of research infrastructure actually lives, and a
// comparison that only spoke to systems programmers would be
// answering a question nobody in this building asked.
//
// It is also the column that makes the DELIVERABLE visible.  The
// others produce an executable; this produces bytecode that needs a
// 300 MB runtime to start, and the startup is a measurable part of a
// short run.  Both facts are reported rather than averaged away: the
// wall clock includes JVM startup, because that is what a user waits
// for, and a second figure gives the in-process compute time, because
// that is what the JIT eventually achieves.
import java.io.{BufferedOutputStream, FileOutputStream}

object Mandel:
  val MaxIter = 50
  val Limit = 4.0

  def main(args: Array[String]): Unit =
    if args.length < 2 then
      System.err.println("usage: Mandel N OUTFILE")
      sys.exit(1)
    var n = args(0).toLong
    if n < 8 then n = 8
    n -= n % 8

    val t0 = System.nanoTime()
    val out = new BufferedOutputStream(new FileOutputStream(args(1)))
    out.write(s"P4\n$n $n\n".getBytes("US-ASCII"))

    val row = new Array[Byte]((n / 8).toInt)
    val inv = 2.0 / n.toDouble

    var y = 0L
    while y < n do
      val ci = y.toDouble * inv - 1.0
      var x = 0L
      while x < n do
        var bits = 0L
        var k = 0L
        while k < 8 do
          val cr = (x + k).toDouble * inv - 1.5
          var zr = 0.0
          var zi = 0.0
          var bit = 1L
          var iter = 0
          while iter < MaxIter do
            val t = zr * zr - zi * zi + cr
            zi = 2.0 * zr * zi + ci
            zr = t
            if zr * zr + zi * zi > Limit then
              bit = 0L
              iter = MaxIter
            else iter += 1
          bits = bits * 2 + bit
          k += 1
        row((x / 8).toInt) = bits.toByte
        x += 8
      out.write(row)
      y += 1
    out.close()

    // stderr, so the file and the exit status stay comparable
    System.err.println(f"compute ${(System.nanoTime() - t0) / 1e9}%.3fs")
