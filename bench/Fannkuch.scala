// fannkuch-redux in Scala, the same algorithm as Fannkuch.m9.
//
// The interesting thing about this column is that it is CHECKED and
// cannot be otherwise: every Array access on the JVM carries a bounds
// check the language gives you no switch to remove, which is exactly
// M9's position.  Integer overflow, on the other hand, wraps silently
// -- Scala has Rust's default and no flag to change it -- so this
// program is half of M9's contract and half of Rust's.
object Fannkuch:
  val MaxN = 16

  def run(n: Int): (Long, Int) =
    val perm = new Array[Int](MaxN)
    val perm1 = new Array[Int](MaxN)
    val count = new Array[Int](MaxN)
    var i = 0
    while i < n do { perm1(i) = i; i += 1 }
    var r = n
    var maxFlips = 0
    var permCount = 0L
    var checksum = 0L
    var done = false
    while !done do
      while r != 1 do
        count(r - 1) = r
        r -= 1
      i = 0
      while i < n do { perm(i) = perm1(i); i += 1 }
      var flips = 0
      var k = perm(0)
      while k != 0 do
        var a = 0
        var b = k
        while a < b do
          val t = perm(a); perm(a) = perm(b); perm(b) = t
          a += 1; b -= 1
        flips += 1
        k = perm(0)
      if flips > maxFlips then maxFlips = flips
      if permCount % 2 == 0 then checksum += flips else checksum -= flips
      permCount += 1
      var advanced = false
      while !advanced && !done do
        if r == n then done = true
        else
          val p0 = perm1(0)
          i = 0
          while i < r do { perm1(i) = perm1(i + 1); i += 1 }
          perm1(r) = p0
          count(r) -= 1
          if count(r) > 0 then advanced = true else r += 1
    (checksum, maxFlips)

  def main(args: Array[String]): Unit =
    var n = if args.length >= 1 then args(0).toInt else 10
    if n < 1 then n = 1
    if n > MaxN then n = MaxN
    val (checksum, maxFlips) = run(n)
    println(checksum)
    println(s"Pfannkuchen($n) = $maxFlips")
