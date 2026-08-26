use std::env;

fn required(name: &str, allow_host_default: bool, default: &str) -> String {
    let value = match env::var(name) {
        Ok(value) => value,
        Err(_) if allow_host_default => default.to_owned(),
        Err(_) => panic!("missing required build identity {name}"),
    };
    if value.is_empty() {
        panic!("empty required build identity {name}");
    }
    value
}
fn hex(name: &str, len: usize, allow_host_default: bool, default: &str) -> String {
    let value = required(name, allow_host_default, default);
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
    for name in [
        "SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT",
        "SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH",
        "SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT",
    ] {
        println!("cargo:rerun-if-env-changed={name}");
    }
    let wasm_target = env::var("TARGET").as_deref() == Ok("wasm32-unknown-unknown");
    // Host unit tests may use visibly dirty identities; wasm builds must always
    // receive explicit release identity so it cannot leak into Web artifacts.
    println!(
        "cargo:rustc-env=SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT={}",
        hex(
            "SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT",
            40,
            !wasm_target,
            "0000000000000000000000000000000000000000"
        )
    );
    println!(
        "cargo:rustc-env=SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH={}",
        hex(
            "SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH",
            64,
            !wasm_target,
            "0000000000000000000000000000000000000000000000000000000000000000"
        )
    );
    println!("cargo:rustc-env=SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT={}", {
        let dirty = match env::var("SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT") {
            Ok(value) => value,
            Err(_) if wasm_target => {
                panic!("missing required build identity SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT")
            }
            Err(_) => "true".into(),
        };
        if dirty != "true" && dirty != "false" {
            panic!("invalid build identity SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT");
        }
        dirty
    });
    println!("cargo:rustc-env=SYNAPTIC_PROCGEN_TARGET=wasm32-unknown-unknown");
}
