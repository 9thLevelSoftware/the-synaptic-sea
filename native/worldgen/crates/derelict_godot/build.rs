use derelict_core::manifest::BuildManifest;
use serde_json::Value;
use std::{
    env, fs,
    path::{Path, PathBuf},
    process::Command,
};

const TARGET: &str = "x86_64-pc-windows-msvc";
const CONTENT_HASH: &str = "content_manifest_hash";

fn valid_hex(value: &str, len: usize) -> bool {
    value.len() == len
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        && value == value.to_ascii_lowercase()
}
fn fail(message: &str) -> ! {
    panic!("derelict_godot build metadata: {message}")
}
fn git_dirty(root: &Path, source: &str) -> Result<bool, String> {
    let diff = Command::new("git")
        .args([
            "-C",
            root.to_str().unwrap(),
            "diff",
            "--quiet",
            source,
            "--",
            "native/worldgen",
        ])
        .status()
        .map_err(|e| e.to_string())?;
    let diff_dirty = match diff.code() {
        Some(0) => false,
        Some(1) => true,
        _ => return Err("git diff failed".into()),
    };
    let status = Command::new("git")
        .args([
            "-C",
            root.to_str().unwrap(),
            "status",
            "--porcelain",
            "--untracked-files=all",
            "--",
            "native/worldgen",
        ])
        .output()
        .map_err(|e| e.to_string())?;
    if !status.status.success() {
        return Err("git status failed".into());
    }
    Ok(diff_dirty || !status.stdout.is_empty())
}
fn require_commit(root: &Path, source: &str) {
    let status = Command::new("git")
        .args([
            "-C",
            root.to_str().unwrap(),
            "cat-file",
            "-e",
            &format!("{source}^{{commit}}"),
        ])
        .status()
        .unwrap_or_else(|_| fail("unable to run git cat-file"));
    if !status.success() {
        fail("source commit is not present in Git");
    }
}

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
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
    let (source, content) = if target != TARGET {
        match (source_env, content_env) {
            (Some(source), Some(content)) => (source, content),
            _ => fail("source and content identity overrides must be supplied together for non-win64 targets"),
        }
    } else if let (Some(source), Some(content)) = (source_env.clone(), content_env.clone()) {
        (source, content)
    } else {
        let text = fs::read_to_string(&manifest_path)
            .unwrap_or_else(|_| fail("checked win64 build manifest is missing"));
        let manifest = BuildManifest::from_json(&text)
            .unwrap_or_else(|_| fail("checked win64 build manifest violates the shared contract"));
        let value: Value = serde_json::from_str(&text)
            .unwrap_or_else(|_| fail("checked win64 build manifest is invalid JSON"));
        let manifest_source = value
            .get("rust_source_commit")
            .and_then(Value::as_str)
            .unwrap_or_else(|| fail("manifest source commit missing"))
            .to_owned();
        let manifest_content = value
            .get(CONTENT_HASH)
            .and_then(Value::as_str)
            .unwrap_or_else(|| fail("manifest content hash missing"))
            .to_owned();
        if manifest.generator_version != 2 || manifest.target != TARGET {
            fail("checked win64 manifest identity mismatch");
        }
        let schemas = value
            .get("export_schemas")
            .and_then(Value::as_object)
            .unwrap_or_else(|| fail("manifest export schemas missing"));
        let expected = [
            ("procgen_request", "procgen-request-1"),
            ("procgen_bundle", "procgen-bundle-1"),
            ("world_ir", "world-ir-1"),
            ("site_ir", "site-ir-1"),
            ("gameplay_ir", "gameplay-ir-1"),
            ("presentation_ir", "presentation-ir-1"),
            ("generation_trace", "generation-trace-1"),
            ("adaptive_proposal", "adaptive-proposal-1"),
        ];
        if expected
            .iter()
            .any(|(name, expected)| schemas.get(*name).and_then(Value::as_str) != Some(*expected))
        {
            fail("manifest export schemas are not v1");
        }
        (
            source_env.unwrap_or(manifest_source),
            content_env.unwrap_or(manifest_content),
        )
    };
    if !valid_hex(&source, 40) {
        fail("source commit must be 40 lowercase hexadecimal characters");
    }
    if !valid_hex(&content, 64) {
        fail("content manifest hash must be 64 lowercase hexadecimal characters");
    }
    let root = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap()).join("../../../../");
    require_commit(&root, &source);
    let dirty = match env::var("SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT") {
        Ok(value) if value == "true" => true,
        Ok(value) if value == "false" => false,
        Ok(_) => fail("dirty-development override must be true or false"),
        Err(_) => git_dirty(&root, &source).unwrap_or_else(|e| fail(&e)),
    };
    println!("cargo:rustc-env=SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT={source}");
    println!("cargo:rustc-env=SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH={content}");
    println!("cargo:rustc-env=SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT={dirty}");
    println!("cargo:rustc-env=SYNAPTIC_PROCGEN_TARGET={target}");
}
