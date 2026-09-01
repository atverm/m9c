// binary-trees in Scala, the same algorithm as BinTrees.m9.
//
// This is the column where the JVM is supposed to shine and where the
// comparison is least like the others: nothing is freed here, because
// nothing CAN be -- the garbage collector decides when, and the
// benchmark's whole subject is who pays for the deallocation and
// when.  M9's answer is a pool reset at the end of a frame, Rust's is
// an arena crate or a Box drop, Object Pascal's is Dispose, and
// Scala's is "later, by someone else, off the clock you are reading".
//
// So the number below is honest about wall time and quiet about the
// GC work that a longer-running process would eventually do.  Stated
// rather than averaged away.
case class Node(left: Node | Null, right: Node | Null)

object BinTrees:
  val MinDepth = 4

  def make(depth: Int): Node =
    if depth > 0 then Node(make(depth - 1), make(depth - 1))
    else Node(null, null)

  def check(n: Node): Int =
    var c = 1
    val l = n.left
    if l != null then c += check(l.asInstanceOf[Node])
    val r = n.right
    if r != null then c += check(r.asInstanceOf[Node])
    c

  def main(args: Array[String]): Unit =
    var maxDepth = if args.length >= 1 then args(0).toInt else 18
    if maxDepth < MinDepth + 2 then maxDepth = MinDepth + 2

    println(s"stretch tree of depth ${maxDepth + 1}  check: ${check(make(maxDepth + 1))}")

    val longLived = make(maxDepth)

    var depth = MinDepth
    while depth <= maxDepth do
      var iters = 1
      var i = 1
      while i <= maxDepth - depth + MinDepth do { iters *= 2; i += 1 }
      var sum = 0
      i = 1
      while i <= iters do { sum += check(make(depth)); i += 1 }
      println(s"$iters trees of depth $depth  check: $sum")
      depth += 2

    println(s"long lived tree of depth $maxDepth  check: ${check(longLived)}")
