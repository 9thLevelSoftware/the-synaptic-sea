//! Golden-hash tests: generated ships for a committed set of inputs must
//! hash to committed values. Any intentional generation change requires
//! regenerating the hash file in the same commit (and bumping
//! GENERATOR_VERSION):
//!
//! ```text
//! UPDATE_GOLDEN=1 cargo test -p derelict_core --test golden
//! ```

use derelict_core::{GenData, GenParams};
use std::fmt::Write as _;

const CASES: &[(&str, u64, Option<u16>)] = &[
    ("shuttle", 1, None),
    ("shuttle", 99, Some(2000)),
    ("corvette", 7, None),
    ("corvette", 1234, Some(9500)),
    ("freighter", 42, None),
    ("freighter", 8, Some(1500)),
    ("frigate", 3, None),
    ("frigate", 12, Some(600)),
];

fn golden_path() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/golden/hashes.txt")
}

fn compute() -> String {
    let data = GenData::default_bundle().unwrap();
    let mut out = String::new();
    for (arch, seed, intact) in CASES {
        let mut params = GenParams::new(arch);
        params.intactness_override = *intact;
        let ship = derelict_core::generate_ship(*seed, &params, &data).unwrap();
        let bytes = bincode::serde::encode_to_vec(&ship, bincode::config::standard()).unwrap();
        let hash = blake3::hash(&bytes);
        writeln!(out, "{arch} {seed} {:?} {}", intact, hash.to_hex()).unwrap();
    }
    out
}

#[test]
fn golden_hashes_match() {
    let current = compute();
    let path = golden_path();
    if std::env::var("UPDATE_GOLDEN").is_ok() {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, &current).unwrap();
        eprintln!("golden hashes updated at {}", path.display());
        return;
    }
    let committed = std::fs::read_to_string(&path).unwrap_or_else(|_| {
        panic!(
            "golden hash file missing; run UPDATE_GOLDEN=1 cargo test -p derelict_core --test golden"
        )
    });
    assert_eq!(
        committed.replace("\r\n", "\n"),
        current,
        "generated output changed — if intentional, bump GENERATOR_VERSION and regenerate goldens"
    );
}
