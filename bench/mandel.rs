// mandelbrot in Rust: the same algorithm as Mandel.m9 and mandel_c.c,
// written the way the language wants to be written but without SIMD
// intrinsics, rayon, or the Benchmarks Game entry's hand-tuning --
// the comparison is between five straightforward programs.
//
// Indexing goes through a Vec, so Rust's bounds checks are on here in
// the same places M9's are; the escape loop has no subscripting in
// either, which is the point of the benchmark.
use std::env;
use std::fs::File;
use std::io::{BufWriter, Write};

const MAXITER: i64 = 50;
const LIMIT: f64 = 4.0;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: mandel N OUTFILE");
        std::process::exit(1);
    }
    let mut n: i64 = args[1].parse().expect("mandel: bad argument");
    if n < 8 {
        n = 8;
    }
    n -= n % 8;

    let f = File::create(&args[2]).expect("mandel: cannot write");
    let mut out = BufWriter::new(f);
    write!(out, "P4\n{} {}\n", n, n).unwrap();

    let mut row = vec![0u8; (n / 8) as usize];
    let inv = 2.0 / n as f64;

    for y in 0..n {
        let ci = y as f64 * inv - 1.0;
        let mut x = 0i64;
        while x < n {
            let mut bits: i64 = 0;
            for k in 0..8i64 {
                let cr = (x + k) as f64 * inv - 1.5;
                let mut zr = 0.0f64;
                let mut zi = 0.0f64;
                let mut bit: i64 = 1;
                for _ in 0..MAXITER {
                    let t = zr * zr - zi * zi + cr;
                    zi = 2.0 * zr * zi + ci;
                    zr = t;
                    if zr * zr + zi * zi > LIMIT {
                        bit = 0;
                        break;
                    }
                }
                bits = bits * 2 + bit;
            }
            row[(x / 8) as usize] = bits as u8;
            x += 8;
        }
        out.write_all(&row).unwrap();
    }
    out.flush().unwrap();
}
