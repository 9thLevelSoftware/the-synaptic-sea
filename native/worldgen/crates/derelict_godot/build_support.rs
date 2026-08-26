use derelict_core::manifest::BuildManifest;
use std::{
    path::PathBuf,
    process::{Command, Stdio},
};

pub const WIN_TARGET: &str = "x86_64-pc-windows-msvc";

pub fn valid_hex(value: &str, len: usize) -> bool {
    value.len() == len
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        && value == value.to_ascii_lowercase()
}

fn parse_dirty_override(value: Option<&str>) -> Result<Option<bool>, String> {
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
    pub dirty: bool,
}

pub trait GitProbe {
    fn diff_exit(&self, source: &str) -> Result<i32, String>;
    fn status(&self) -> Result<(i32, bool), String>;
    fn commit_exists(&self, source: &str) -> Result<bool, String>;
}

pub struct CommandProbe {
    root: PathBuf,
    scope: String,
}

impl CommandProbe {
    pub fn new(root: PathBuf, scope: impl Into<String>) -> Self {
        Self {
            root,
            scope: scope.into(),
        }
    }
}

impl GitProbe for CommandProbe {
    fn diff_exit(&self, source: &str) -> Result<i32, String> {
        Command::new("git")
            .arg("-C")
            .arg(&self.root)
            .args(["diff", "--quiet", source, "--", &self.scope])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|status| status.code().unwrap_or(-1))
            .map_err(|error| error.to_string())
    }

    fn status(&self) -> Result<(i32, bool), String> {
        let output = Command::new("git")
            .arg("-C")
            .arg(&self.root)
            .args([
                "status",
                "--porcelain",
                "--untracked-files=all",
                "--",
                &self.scope,
            ])
            .output()
            .map_err(|error| error.to_string())?;
        Ok((
            output.status.code().unwrap_or(-1),
            !output.stdout.is_empty(),
        ))
    }

    fn commit_exists(&self, source: &str) -> Result<bool, String> {
        Command::new("git")
            .arg("-C")
            .arg(&self.root)
            .args(["cat-file", "-e", &format!("{source}^{{commit}}")])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|status| status.success())
            .map_err(|error| error.to_string())
    }
}

pub fn classify_dirty<P: GitProbe>(probe: &P, source: &str) -> Result<bool, String> {
    let diff_dirty = match probe.diff_exit(source)? {
        0 => false,
        1 => true,
        _ => return Err("git diff failed".into()),
    };
    let (status, scoped_changes) = probe.status()?;
    if status != 0 {
        return Err("git status failed".into());
    }
    Ok(diff_dirty || scoped_changes)
}

pub fn select<P: GitProbe>(input: Inputs<'_>, probe: &P) -> Result<Selected, String> {
    let (source, content) = if input.target != WIN_TARGET {
        match (input.source_override, input.content_override) {
            (Some(source), Some(content)) => (source.to_owned(), content.to_owned()),
            _ => {
                return Err(
                    "source and content identity overrides must be supplied together for non-win64 targets"
                        .into(),
                );
            }
        }
    } else if let (Some(source), Some(content)) = (input.source_override, input.content_override) {
        (source.to_owned(), content.to_owned())
    } else {
        let text = input
            .checked_manifest
            .ok_or("checked win64 build manifest is missing")?;
        let manifest = BuildManifest::from_json_platform_v3(text)
            .map_err(|_| "checked win64 build manifest violates the shared contract")?;
        if manifest.target != WIN_TARGET || manifest.generator_version != 3 {
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
    if !probe.commit_exists(&source)? {
        return Err("source commit is not present in Git".into());
    }

    let dirty = match parse_dirty_override(input.dirty_override)? {
        Some(value) => value,
        None => classify_dirty(probe, &source)?,
    };
    Ok(Selected {
        source,
        content,
        dirty,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        fs,
        process::Output,
        sync::atomic::{AtomicU64, Ordering},
    };

    const SOURCE: &str = "b78fedf2624c2d54f0f42b6c0ad3c488fbd9e6a9";
    const SOURCE_OVERRIDE: &str = "1111111111111111111111111111111111111111";
    const HASH: &str = "e0364ba52fbf0b1c629c676d622fdc2ffd6964bee47c11cad58c320de22a7c1a";
    const HASH_OVERRIDE: &str = "2222222222222222222222222222222222222222222222222222222222222222";

    struct Probe {
        diff: i32,
        status: i32,
        changes: bool,
        commit: bool,
        diff_error: bool,
        status_error: bool,
        commit_error: bool,
    }

    impl Default for Probe {
        fn default() -> Self {
            Self {
                diff: 0,
                status: 0,
                changes: false,
                commit: true,
                diff_error: false,
                status_error: false,
                commit_error: false,
            }
        }
    }

    impl GitProbe for Probe {
        fn diff_exit(&self, _: &str) -> Result<i32, String> {
            if self.diff_error {
                Err("diff unavailable".into())
            } else {
                Ok(self.diff)
            }
        }

        fn status(&self) -> Result<(i32, bool), String> {
            if self.status_error {
                Err("status unavailable".into())
            } else {
                Ok((self.status, self.changes))
            }
        }

        fn commit_exists(&self, _: &str) -> Result<bool, String> {
            if self.commit_error {
                Err("cat-file unavailable".into())
            } else {
                Ok(self.commit)
            }
        }
    }

    fn manifest() -> String {
        format!(
            r#"{{"manifest_schema":"procgen-build-manifest-1","rust_source_commit":"{SOURCE}","generator_version":3,"content_manifest_path":"data/procgen/manifests/content_manifest.json","content_manifest_hash":"{HASH}","target":"x86_64-pc-windows-msvc","artifact":{{"kind":"gdextension","path":"addons/derelict/bin/win64/derelict_godot.dll","sha256":"{HASH}"}},"export_schemas":{{"procgen_request":"procgen-request-1","procgen_bundle":"procgen-bundle-3","world_ir":"world-ir-2","site_ir":"site-ir-2","gameplay_ir":"gameplay-ir-1","presentation_ir":"presentation-ir-1","generation_trace":"generation-trace-2","adaptive_proposal":"adaptive-proposal-1"}}}}"#
        )
    }

    fn inputs<'a>(checked_manifest: Option<&'a str>) -> Inputs<'a> {
        Inputs {
            target: WIN_TARGET,
            source_override: None,
            content_override: None,
            dirty_override: Some("false"),
            checked_manifest,
        }
    }

    #[test]
    fn override_and_target_matrix_uses_one_selection_path() {
        let checked = manifest();
        let selected = select(inputs(Some(&checked)), &Probe::default()).unwrap();
        assert_eq!(selected.source, SOURCE);
        assert_eq!(selected.content, HASH);
        assert!(!selected.dirty);

        let source_only = select(
            Inputs {
                source_override: Some(SOURCE_OVERRIDE),
                ..inputs(Some(&checked))
            },
            &Probe::default(),
        )
        .unwrap();
        assert_eq!(source_only.source, SOURCE_OVERRIDE);
        assert_eq!(source_only.content, HASH);

        let content_only = select(
            Inputs {
                content_override: Some(HASH_OVERRIDE),
                ..inputs(Some(&checked))
            },
            &Probe::default(),
        )
        .unwrap();
        assert_eq!(content_only.source, SOURCE);
        assert_eq!(content_only.content, HASH_OVERRIDE);

        let full = select(
            Inputs {
                source_override: Some(SOURCE_OVERRIDE),
                content_override: Some(HASH_OVERRIDE),
                ..inputs(None)
            },
            &Probe::default(),
        )
        .unwrap();
        assert_eq!(full.source, SOURCE_OVERRIDE);
        assert_eq!(full.content, HASH_OVERRIDE);

        for (source, content) in [(None, None), (Some(SOURCE), None), (None, Some(HASH))] {
            assert!(select(
                Inputs {
                    target: "wasm32-unknown-unknown",
                    source_override: source,
                    content_override: content,
                    dirty_override: Some("false"),
                    checked_manifest: None,
                },
                &Probe::default(),
            )
            .is_err());
        }
        assert!(select(
            Inputs {
                target: "wasm32-unknown-unknown",
                source_override: Some(SOURCE),
                content_override: Some(HASH),
                dirty_override: Some("false"),
                checked_manifest: None,
            },
            &Probe::default(),
        )
        .is_ok());
    }

    #[test]
    fn malformed_manifest_identity_dirty_and_commit_fail_closed() {
        let checked = manifest();
        for malformed in [
            checked.replace("procgen-build-manifest-1", "bad-schema"),
            checked.replace("\"generator_version\":3", "\"generator_version\":2"),
            checked.replace("procgen-request-1", "bad-request-schema"),
            checked.replacen('{', "{\"unknown\":true,", 1),
        ] {
            assert!(select(inputs(Some(&malformed)), &Probe::default()).is_err());
        }

        let short_source = "0".repeat(39);
        assert!(select(
            Inputs {
                source_override: Some(&short_source),
                content_override: Some(HASH),
                ..inputs(None)
            },
            &Probe::default(),
        )
        .is_err());
        assert!(select(
            Inputs {
                dirty_override: Some("maybe"),
                ..inputs(Some(&checked))
            },
            &Probe::default(),
        )
        .is_err());
        assert!(select(
            inputs(Some(&checked)),
            &Probe {
                commit: false,
                ..Probe::default()
            },
        )
        .is_err());
        assert!(select(
            inputs(Some(&checked)),
            &Probe {
                commit_error: true,
                ..Probe::default()
            },
        )
        .is_err());

        let selected = select(
            Inputs {
                dirty_override: Some("true"),
                ..inputs(Some(&checked))
            },
            &Probe {
                diff_error: true,
                status_error: true,
                ..Probe::default()
            },
        )
        .unwrap();
        assert!(
            selected.dirty,
            "explicit dirty identity must bypass Git state"
        );
    }

    #[test]
    fn dirty_classification_handles_clean_changes_and_command_failures() {
        assert!(!classify_dirty(&Probe::default(), SOURCE).unwrap());
        assert!(classify_dirty(
            &Probe {
                diff: 1,
                ..Probe::default()
            },
            SOURCE,
        )
        .unwrap());
        assert!(classify_dirty(
            &Probe {
                changes: true,
                ..Probe::default()
            },
            SOURCE,
        )
        .unwrap());
        for probe in [
            Probe {
                diff: 2,
                ..Probe::default()
            },
            Probe {
                diff_error: true,
                ..Probe::default()
            },
            Probe {
                status: 1,
                ..Probe::default()
            },
            Probe {
                status_error: true,
                ..Probe::default()
            },
        ] {
            assert!(classify_dirty(&probe, SOURCE).is_err());
        }
    }

    static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

    struct TempRepo(PathBuf);

    impl TempRepo {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "synaptic-procgen-metadata-{}-{}",
                std::process::id(),
                TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(path.join("native/worldgen")).unwrap();
            Self(path)
        }

        fn git(&self, args: &[&str]) -> Output {
            Command::new("git")
                .arg("-C")
                .arg(&self.0)
                .args(args)
                .output()
                .unwrap()
        }

        fn git_ok(&self, args: &[&str]) {
            let output = self.git(args);
            assert!(
                output.status.success(),
                "git {:?} failed: {}",
                args,
                String::from_utf8_lossy(&output.stderr)
            );
        }
    }

    impl Drop for TempRepo {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn command_probe_detects_tracked_staged_and_untracked_scope() {
        let repo = TempRepo::new();
        let tracked = repo.0.join("native/worldgen/tracked.txt");
        fs::write(&tracked, "baseline\n").unwrap();
        repo.git_ok(&["init", "--quiet"]);
        repo.git_ok(&["config", "user.email", "procgen-tests@example.invalid"]);
        repo.git_ok(&["config", "user.name", "Procgen Tests"]);
        repo.git_ok(&["add", "native/worldgen/tracked.txt"]);
        repo.git_ok(&["commit", "--quiet", "-m", "baseline"]);
        let source = String::from_utf8(repo.git(&["rev-parse", "HEAD"]).stdout)
            .unwrap()
            .trim()
            .to_owned();
        let probe = CommandProbe::new(repo.0.clone(), "native/worldgen");
        assert!(probe.commit_exists(&source).unwrap());
        assert!(!probe.commit_exists(&"0".repeat(40)).unwrap());
        assert!(!classify_dirty(&probe, &source).unwrap());

        fs::write(repo.0.join("outside.txt"), "outside scope\n").unwrap();
        assert!(!classify_dirty(&probe, &source).unwrap());

        fs::write(&tracked, "modified\n").unwrap();
        assert!(classify_dirty(&probe, &source).unwrap());
        repo.git_ok(&["add", "native/worldgen/tracked.txt"]);
        assert!(classify_dirty(&probe, &source).unwrap());

        fs::write(&tracked, "baseline\n").unwrap();
        repo.git_ok(&["add", "native/worldgen/tracked.txt"]);
        assert!(!classify_dirty(&probe, &source).unwrap());

        fs::write(repo.0.join("native/worldgen/untracked.txt"), "untracked\n").unwrap();
        assert!(classify_dirty(&probe, &source).unwrap());
    }

    #[test]
    fn command_probe_fails_closed_outside_a_repository() {
        let missing = std::env::temp_dir().join(format!(
            "synaptic-procgen-missing-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        let probe = CommandProbe::new(missing, "native/worldgen");
        assert!(classify_dirty(&probe, SOURCE).is_err());
        assert!(!probe.commit_exists(SOURCE).unwrap());
    }
}
