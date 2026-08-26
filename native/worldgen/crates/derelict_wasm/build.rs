use std::env;
mod build_support;

fn main() {
    for name in [
        "SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT",
        "SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH",
        "SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT",
    ] {
        println!("cargo:rerun-if-env-changed={name}");
    }
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=build_support.rs");
    let target = env::var("TARGET").unwrap_or_else(|_| panic!("TARGET is missing"));
    let identity = build_support::select(
        &target,
        env::var("SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT")
            .ok()
            .as_deref(),
        env::var("SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH")
            .ok()
            .as_deref(),
        env::var("SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT")
            .ok()
            .as_deref(),
    )
    .unwrap_or_else(|message| panic!("derelict_wasm build metadata: {message}"));
    println!(
        "cargo:rustc-env=SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT={}",
        identity.source
    );
    println!(
        "cargo:rustc-env=SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH={}",
        identity.content
    );
    println!(
        "cargo:rustc-env=SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT={}",
        identity.dirty
    );
    println!(
        "cargo:rustc-env=SYNAPTIC_PROCGEN_TARGET={}",
        build_support::WASM_TARGET
    );
}
