// fannkuch-redux in Rust, the same algorithm as bench/Fannkuch.m9,
// untuned and written the way the loop reads.
//
// This file is compiled TWICE by the runner:
//
//   rustc -O                          release default -- bounds are
//                                     checked, integer overflow is
//                                     NOT: `+` wraps silently
//   rustc -O -C overflow-checks=on    both checked, which is what M9
//                                     has no switch to turn off
//
// The difference between those two runs is the price of the museum's
// founding bug, paid in Rust and declined by its default.
//
// Indexing is written with plain `[]` so the bounds checks are real;
// get_unchecked would measure a different language.

const MAX_N: usize = 16;

fn run(n: usize, checksum: &mut i64) -> i64 {
    let mut perm = [0i64; MAX_N];
    let mut perm1 = [0i64; MAX_N];
    let mut count = [0i64; MAX_N];

    for i in 0..n {
        perm1[i] = i as i64;
    }
    let mut r = n;
    let mut max_flips: i64 = 0;
    let mut perm_count: i64 = 0;
    *checksum = 0;

    loop {
        while r != 1 {
            count[r - 1] = r as i64;
            r -= 1;
        }
        for i in 0..n {
            perm[i] = perm1[i];
        }
        let mut flips: i64 = 0;
        let mut k = perm[0];
        while k != 0 {
            let mut i: usize = 0;
            let mut j: usize = k as usize;
            while i < j {
                let t = perm[i];
                perm[i] = perm[j];
                perm[j] = t;
                i += 1;
                j -= 1;
            }
            flips += 1;
            k = perm[0];
        }
        if flips > max_flips {
            max_flips = flips;
        }
        if perm_count % 2 == 0 {
            *checksum += flips;
        } else {
            *checksum -= flips;
        }
        perm_count += 1;
        loop {
            if r == n {
                return max_flips;
            }
            let p0 = perm1[0];
            for i in 0..r {
                perm1[i] = perm1[i + 1];
            }
            perm1[r] = p0;
            count[r] -= 1;
            if count[r] > 0 {
                break;
            }
            r += 1;
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut n: usize = 10;
    if args.len() > 1 {
        n = args[1].parse().expect("bad n");
    }
    if n < 1 {
        n = 1;
    }
    if n > MAX_N {
        n = MAX_N;
    }
    let mut checksum: i64 = 0;
    let max_flips = run(n, &mut checksum);
    println!("{}", checksum);
    println!("Pfannkuchen({}) = {}", n, max_flips);
}
