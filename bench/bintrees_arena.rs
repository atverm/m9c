// binary-trees, Rust with typed-arena -- which is what the fast
// Benchmarks Game entries actually do.  The point of including it is
// not that arenas are cheating; it is that the fast Rust program has
// to import a crate to get the allocation shape this problem wants,
// while M9 spells the same thing with a local POOL and no dependency.
//
// The arena is per generation, released when the Arena drops, which
// is exactly what BinTrees.m9's Generation does with its local pool.
// Same algorithm, same output text.

use typed_arena::Arena;

struct Node<'a> {
    left: Option<&'a Node<'a>>,
    right: Option<&'a Node<'a>>,
}

const MIN_DEPTH: i64 = 4;

fn make<'a>(arena: &'a Arena<Node<'a>>, depth: i64) -> &'a Node<'a> {
    if depth > 0 {
        let l = make(arena, depth - 1);
        let r = make(arena, depth - 1);
        arena.alloc(Node { left: Some(l), right: Some(r) })
    } else {
        arena.alloc(Node { left: None, right: None })
    }
}

fn check(n: &Node) -> i64 {
    let mut c = 1;
    if let Some(l) = n.left {
        c += check(l);
    }
    if let Some(r) = n.right {
        c += check(r);
    }
    c
}

fn generation(depth: i64, iters: i64) -> i64 {
    let arena: Arena<Node> = Arena::new();
    let mut sum = 0;
    for _ in 1..=iters {
        sum += check(make(&arena, depth));
    }
    sum
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

    {
        let arena: Arena<Node> = Arena::new();
        println!(
            "stretch tree of depth {}  check: {}",
            max_depth + 1,
            check(make(&arena, max_depth + 1))
        );
    }

    let long_arena: Arena<Node> = Arena::new();
    let long_lived = make(&long_arena, max_depth);

    let mut depth = MIN_DEPTH;
    while depth <= max_depth {
        let mut iters: i64 = 1;
        for _ in 1..=(max_depth - depth + MIN_DEPTH) {
            iters *= 2;
        }
        println!(
            "{} trees of depth {}  check: {}",
            iters,
            depth,
            generation(depth, iters)
        );
        depth += 2;
    }

    println!(
        "long lived tree of depth {}  check: {}",
        max_depth,
        check(long_lived)
    );
}
