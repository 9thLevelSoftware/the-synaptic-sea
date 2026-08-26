use std::{env, fs, path::PathBuf};
mod build_support;

const TARGET: &str = build_support::WIN_TARGET;
fn fail(message: &str) -> ! {
    panic!("derelict_godot build metadata: {message}")
}

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=build_support.rs");
    println!("cargo:rerun-if-changed=src");
    let manifest_path = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap())
        .join("../../../../data/procgen/manifests/build/win64.json");
    println!("cargo:rerun-if-changed={}", manifest_path.display());
    for name in [
        "SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT",
        "SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH",
        "SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT",
    ] {
        println!("cargo:rerun-if-env-changed={name}");
    }
    let target = env::var("TARGET").unwrap_or_else(|_| fail("TARGET is missing"));
    let source_env = env::var("SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT").ok();
    let content_env = env::var("SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH").ok();
    let root = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap()).join("../../../../");
    let checked_text = if target == TARGET {
        fs::read_to_string(&manifest_path).ok()
    } else {
        None
    };
    let probe = build_support::CommandProbe::new(root, "native/worldgen");
    let selected = build_support::select(
        build_support::Inputs {
            target: &target,
            source_override: source_env.as_deref(),
            content_override: content_env.as_deref(),
            dirty_override: env::var("SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT")
                .ok()
                .as_deref(),
            checked_manifest: checked_text.as_deref(),
        },
        &probe,
    )
    .unwrap_or_else(|e| fail(&e));
    println!(
        "cargo:rustc-env=SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT={}",
        selected.source
    );
    println!(
        "cargo:rustc-env=SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH={}",
        selected.content
    );
    println!(
        "cargo:rustc-env=SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT={}",
        selected.dirty
    );
    println!("cargo:rustc-env=SYNAPTIC_PROCGEN_TARGET={target}");
}
