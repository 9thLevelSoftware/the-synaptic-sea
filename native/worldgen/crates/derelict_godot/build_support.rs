#![allow(dead_code)]

use derelict_core::manifest::BuildManifest;

pub const WIN_TARGET: &str = "x86_64-pc-windows-msvc";

pub fn valid_hex(value: &str, len: usize) -> bool {
    value.len() == len
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        && value == value.to_ascii_lowercase()
}

pub fn parse_dirty_override(value: Option<&str>) -> Result<Option<bool>, String> {
    match value {
        None => Ok(None),
        Some("true") => Ok(Some(true)),
        Some("false") => Ok(Some(false)),
        Some(_) => Err("dirty-development override must be true or false".into()),
    }
}

pub struct Inputs<'a> {
    pub target: &'a str,
    pub source_override: Option<&'a str>,
    pub content_override: Option<&'a str>,
    pub dirty_override: Option<&'a str>,
    pub checked_manifest: Option<&'a str>,
}
pub struct Selected {
    pub source: String,
    pub content: String,
    pub dirty_override: Option<bool>,
}

pub fn select(input: Inputs<'_>) -> Result<Selected, String> {
    let (source, content) = if input.target != WIN_TARGET {
        match (input.source_override, input.content_override) { (Some(s), Some(c)) => (s.to_owned(), c.to_owned()), _ => return Err("source and content identity overrides must be supplied together for non-win64 targets".into()) }
    } else if let (Some(s), Some(c)) = (input.source_override, input.content_override) {
        (s.to_owned(), c.to_owned())
    } else {
        let text = input
            .checked_manifest
            .ok_or("checked win64 build manifest is missing")?;
        let manifest = BuildManifest::from_json(text)
            .map_err(|_| "checked win64 build manifest violates the shared contract")?;
        if manifest.target != WIN_TARGET || manifest.generator_version != 2 {
            return Err("checked win64 manifest identity mismatch".into());
        }
        (
            input
                .source_override
                .unwrap_or(&manifest.rust_source_commit)
                .to_owned(),
            input
                .content_override
                .unwrap_or(&manifest.content_manifest_hash)
                .to_owned(),
        )
    };
    if !valid_hex(&source, 40) {
        return Err("source commit must be 40 lowercase hexadecimal characters".into());
    }
    if !valid_hex(&content, 64) {
        return Err("content manifest hash must be 64 lowercase hexadecimal characters".into());
    }
    Ok(Selected {
        source,
        content,
        dirty_override: parse_dirty_override(input.dirty_override)?,
    })
}

pub trait GitProbe {
    fn diff_exit(&self) -> Result<i32, String>;
    fn status(&self) -> Result<(i32, bool), String>;
}
pub fn classify_dirty<P: GitProbe>(probe: &P) -> Result<bool, String> {
    let diff = match probe.diff_exit()? {
        0 => false,
        1 => true,
        _ => return Err("git diff failed".into()),
    };
    let (status, scoped_changes) = probe.status()?;
    if status != 0 {
        return Err("git status failed".into());
    }
    Ok(diff || scoped_changes)
}

#[cfg(test)]
mod tests {
    use super::*;
    const SOURCE: &str = "b78fedf2624c2d54f0f42b6c0ad3c488fbd9e6a9";
    const HASH: &str = "e45770cf36ca296644b291a1c12d750281c8fcd3e520430b3ae2995d03ab14d2";
    fn manifest() -> String {
        format!(
            r#"{{"manifest_schema":"procgen-build-manifest-1","rust_source_commit":"{SOURCE}","generator_version":2,"content_manifest_path":"data/procgen/manifests/content_manifest.json","content_manifest_hash":"{HASH}","target":"x86_64-pc-windows-msvc","artifact":{{"kind":"gdextension","path":"addons/derelict/bin/win64/derelict_godot.dll","sha256":"{HASH}"}},"export_schemas":{{"procgen_request":"procgen-request-1","procgen_bundle":"procgen-bundle-1","world_ir":"world-ir-1","site_ir":"site-ir-1","gameplay_ir":"gameplay-ir-1","presentation_ir":"presentation-ir-1","generation_trace":"generation-trace-1","adaptive_proposal":"adaptive-proposal-1"}}}}"#
        )
    }
    #[test]
    fn override_matrix_and_validation_are_deterministic() {
        let checked = manifest();
        assert_eq!(
            select(Inputs {
                target: WIN_TARGET,
                source_override: None,
                content_override: None,
                dirty_override: Some("false"),
                checked_manifest: Some(&checked)
            })
            .unwrap()
            .source,
            SOURCE
        );
        assert_eq!(
            select(Inputs {
                target: WIN_TARGET,
                source_override: Some(SOURCE),
                content_override: None,
                dirty_override: None,
                checked_manifest: Some(&checked)
            })
            .unwrap()
            .content,
            HASH
        );
        assert!(select(Inputs {
            target: "aarch64-unknown-linux-gnu",
            source_override: None,
            content_override: None,
            dirty_override: None,
            checked_manifest: None
        })
        .is_err());
        assert!(select(Inputs {
            target: WIN_TARGET,
            source_override: Some("A"),
            content_override: Some(HASH),
            dirty_override: None,
            checked_manifest: Some(&checked)
        })
        .is_err());
        assert!(select(Inputs {
            target: WIN_TARGET,
            source_override: Some("0".repeat(39).leak()),
            content_override: Some(HASH),
            dirty_override: None,
            checked_manifest: Some(&checked)
        })
        .is_err());
        assert!(parse_dirty_override(Some("maybe")).is_err());
        assert_eq!(
            select(Inputs {
                target: WIN_TARGET,
                source_override: Some(SOURCE),
                content_override: Some(HASH),
                dirty_override: Some("true"),
                checked_manifest: Some(&checked)
            })
            .unwrap()
            .dirty_override,
            Some(true)
        );
    }
    struct Probe {
        diff: i32,
        status: i32,
        changes: bool,
    }
    impl GitProbe for Probe {
        fn diff_exit(&self) -> Result<i32, String> {
            Ok(self.diff)
        }
        fn status(&self) -> Result<(i32, bool), String> {
            Ok((self.status, self.changes))
        }
    }
    #[test]
    fn dirty_classification_covers_clean_tracked_staged_untracked_and_failures() {
        assert!(!classify_dirty(&Probe {
            diff: 0,
            status: 0,
            changes: false
        })
        .unwrap());
        assert!(classify_dirty(&Probe {
            diff: 1,
            status: 0,
            changes: false
        })
        .unwrap());
        assert!(classify_dirty(&Probe {
            diff: 0,
            status: 0,
            changes: true
        })
        .unwrap());
        assert!(classify_dirty(&Probe {
            diff: 2,
            status: 0,
            changes: false
        })
        .is_err());
        assert!(classify_dirty(&Probe {
            diff: 0,
            status: 1,
            changes: false
        })
        .is_err());
    }
    #[test]
    fn malformed_checked_manifest_fails_full_contract() {
        let mut text = manifest();
        text = text.replace("procgen-build-manifest-1", "bad");
        assert!(select(Inputs {
            target: WIN_TARGET,
            source_override: None,
            content_override: None,
            dirty_override: None,
            checked_manifest: Some(&text)
        })
        .is_err());
    }
}
