// binary-trees, idiomatic Rust: Box, one allocation per node, freed
// by drop.  This is what a Rust programmer writes before reaching
// for an arena crate, and it is the honest baseline for "what the
// language gives you".  The Benchmarks Game entries do NOT look
// like this -- see bintrees_arena.rs for why that matters.
//
// Same algorithm and same output text as bench/BinTrees.m9, so the
// runner can compare bytes and not just clocks.

struct Node {
    left: Option<Box<Node>>,
    right: Option<Box<Node>>,
}

const MIN_DEPTH: i64 = 4;

fn make(depth: i64) -> Box<Node> {
    if depth > 0 {
        Box::new(Node {
            left: Some(make(depth - 1)),
            right: Some(make(depth - 1)),
        })
    } else {
        Box::new(Node { left: None, right: None })
    }
}

fn check(n: &Node) -> i64 {
    let mut c = 1;
    if let Some(l) = &n.left {
        c += check(l);
    }
    if let Some(r) = &n.right {
        c += check(r);
    }
    c
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut max_depth: i64 = 18;
    if args.len() > 1 {
        max_depth = args[1].parse().expect("bad depth argument");
    }
    if max_depth < MIN_DEPTH + 2 {
        max_depth = MIN_DEPTH + 2;
    }

    println!(
        "stretch tree of depth {}  check: {}",
        max_depth + 1,
        check(&make(max_depth + 1))
    );

    let long_lived = make(max_depth);

    let mut depth = MIN_DEPTH;
    while depth <= max_depth {
        let mut iters: i64 = 1;
        for _ in 1..=(max_depth - depth + MIN_DEPTH) {
            iters *= 2;
        }
        let mut sum: i64 = 0;
        for _ in 1..=iters {
            sum += check(&make(depth));
        }
        println!("{} trees of depth {}  check: {}", iters, depth, sum);
        depth += 2;
    }

    println!(
        "long lived tree of depth {}  check: {}",
        max_depth,
        check(&long_lived)
    );
}
