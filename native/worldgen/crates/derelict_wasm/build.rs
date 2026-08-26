use std::env;

fn required(name: &str) -> String {
    let value = env::var(name).unwrap_or_else(|_| panic!("missing required build identity {name}"));
    if value.is_empty() {
        panic!("empty required build identity {name}");
    }
    value
}
fn hex(name: &str, len: usize) -> String {
    let value = required(name);
    if value.len() != len
        || !value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        panic!("invalid build identity {name}");
    }
    value
}

fn main() {
    println!(
        "cargo:rustc-env=SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT={}",
        hex("SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT", 40)
    );
    println!(
        "cargo:rustc-env=SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH={}",
        hex("SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH", 64)
    );
    println!("cargo:rustc-env=SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT={}", {
        let dirty =
            env::var("SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT").unwrap_or_else(|_| "false".into());
        if dirty != "true" && dirty != "false" {
            panic!("invalid build identity SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT");
        }
        dirty
    });
    println!("cargo:rustc-env=SYNAPTIC_PROCGEN_TARGET=wasm32-unknown-unknown");
}
