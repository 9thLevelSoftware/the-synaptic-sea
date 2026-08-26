use derelict_core::procgen::{generate_bundle, ProcgenRequest};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, fs, path::PathBuf};

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Vector {
    name: String,
    request: ProcgenRequest,
    expected_semantic_hash: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    same_semantics_as: Option<String>,
}

fn workspace_paths() -> (PathBuf, PathBuf) {
    let worldgen = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let repository = worldgen.join("../..");
    (
        worldgen.join("tests/adapter_parity/corpus.json"),
        repository.join("data/procgen/manifests/content_manifest.json"),
    )
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let (corpus_path, content_path) = workspace_paths();
    let content: serde_json::Value = serde_json::from_slice(&fs::read(content_path)?)?;
    let content_hash = content
        .get("content_manifest_hash")
        .and_then(serde_json::Value::as_str)
        .filter(|value| {
            value.len() == 64
                && value
                    .bytes()
                    .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
        })
        .ok_or("content manifest has no valid lowercase SHA-256 identity")?;
    let mut vectors: Vec<Vector> = serde_json::from_slice(&fs::read(&corpus_path)?)?;
    let data = derelict_core::GenData::default_bundle()?;
    let mut hashes = BTreeMap::new();
    for vector in &mut vectors {
        vector.request.content_manifest_hash = content_hash.into();
        vector.request.validate()?;
        let mut bundle = generate_bundle(vector.request.clone(), &data)
            .map_err(|error| format!("{} failed: {error:?}", vector.name))?;
        if vector.name.contains("_fractured_") && !bundle.site_ir.ship.fractured {
            let prefix = vector
                .name
                .rsplit_once("_seed")
                .map_or(vector.name.as_str(), |(prefix, _)| prefix)
                .to_owned();
            let mut replacement = None;
            for world_seed in 0..4096 {
                vector.request.world_seed = world_seed;
                let candidate =
                    generate_bundle(vector.request.clone(), &data).map_err(|error| {
                        format!("{} seed {world_seed} failed: {error:?}", vector.name)
                    })?;
                if candidate.site_ir.ship.fractured {
                    replacement = Some((world_seed, candidate));
                    break;
                }
            }
            let (world_seed, candidate) =
                replacement.ok_or("no fractured corpus seed in 0..4096")?;
            vector.name = format!("{prefix}_seed{world_seed}");
            bundle = candidate;
        }
        vector.expected_semantic_hash = bundle.semantic_hash.clone();
        hashes.insert(vector.name.clone(), bundle.semantic_hash);
    }
    for vector in &vectors {
        if let Some(parent) = &vector.same_semantics_as {
            if hashes.get(&vector.name) != hashes.get(parent) {
                return Err(format!(
                    "{} no longer has the same semantics as {parent}",
                    vector.name
                )
                .into());
            }
        }
    }
    fs::write(
        corpus_path,
        format!("{}\n", serde_json::to_string_pretty(&vectors)?),
    )?;
    println!(
        "adapter parity corpus refreshed: vectors={} content_hash={content_hash}",
        vectors.len()
    );
    Ok(())
}
