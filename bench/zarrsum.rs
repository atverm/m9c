// The real workload: read the 4000x4000 f8 bench store (blosc/lz4,
// 500x500 chunks) and compute the NaN-ignoring sum and count.
//
// This is the comparison that matters, because it is the program the
// language was designed for rather than a loop chosen to be timed.
// M9's side is corpus/ZarrStore.m9, already differentially verified
// against the FPC reader and numpy to the last digit; the goldens it
// must reproduce are n = 15800721 and nansum = 6324247734.661942
// (numpy's pairwise sum -- summing in a different order lands a few
// ulps away, which is why the M9 driver documents its own order).
//
// Read honestly: this is NOT apples to apples on I/O. zarrs reads
// the store from the filesystem; M9's ZarrStore is HTTP-only by
// design, so its column carries a localhost HTTP round trip per
// chunk that this one does not. The runner reports both and says so.

use std::sync::Arc;
use zarrs::array::Array;
use zarrs::filesystem::FilesystemStore;

fn main() {
    let path = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "/tmp/m9stores".to_string());

    let store = Arc::new(FilesystemStore::new(&path).expect("open store"));
    let array = Array::open(store, "/bench.zarr").expect("open array");

    let shape = array.shape().to_vec();
    let chunks = array.chunk_grid_shape().expect("chunk grid").to_vec();

    let mut sum: f64 = 0.0;
    let mut n: i64 = 0;

    for ci in 0..chunks[0] {
        for cj in 0..chunks[1] {
            let data: Vec<f64> = array
                .retrieve_chunk_elements(&[ci, cj])
                .expect("retrieve chunk");
            for v in data {
                if !v.is_nan() {
                    sum += v;
                    n += 1;
                }
            }
        }
    }

    println!("shape {}x{}", shape[0], shape[1]);
    println!("n = {}", n);
    println!("nansum = {:.10}", sum);
}
