//! Pure build-identity selection shared by `build.rs` and host tests.

pub const WASM_TARGET: &str = "wasm32-unknown-unknown";
const HOST_SOURCE: &str = "0000000000000000000000000000000000000000";
const HOST_CONTENT: &str = "0000000000000000000000000000000000000000000000000000000000000000";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Identity {
    pub source: String,
    pub content: String,
    pub dirty: bool,
}

pub fn select(
    target: &str,
    source: Option<&str>,
    content: Option<&str>,
    dirty: Option<&str>,
) -> Result<Identity, String> {
    let strict = target == WASM_TARGET;
    let source = select_hex(
        "SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT",
        source,
        40,
        strict,
        HOST_SOURCE,
    )?;
    let content = select_hex(
        "SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH",
        content,
        64,
        strict,
        HOST_CONTENT,
    )?;
    let dirty = match dirty {
        Some("true") => true,
        Some("false") => false,
        Some(_) => return Err("invalid build identity SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT".into()),
        None if strict => {
            return Err("missing required build identity SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT".into())
        }
        None => true,
    };
    Ok(Identity {
        source,
        content,
        dirty,
    })
}

fn select_hex(
    name: &str,
    value: Option<&str>,
    len: usize,
    strict: bool,
    host_default: &str,
) -> Result<String, String> {
    let value = match value {
        Some(value) => value,
        None if strict => return Err(format!("missing required build identity {name}")),
        None => host_default,
    };
    if value.len() != len
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(format!("invalid build identity {name}"));
    }
    Ok(value.into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wasm_requires_every_explicit_valid_identity() {
        let source = "a".repeat(40);
        let content = "b".repeat(64);
        for missing in 0..3 {
            let result = select(
                WASM_TARGET,
                (missing != 0).then_some(source.as_str()),
                (missing != 1).then_some(content.as_str()),
                (missing != 2).then_some("false"),
            );
            assert!(result.is_err(), "missing identity index {missing}");
        }
        assert!(select(WASM_TARGET, Some("A"), Some(&content), Some("false")).is_err());
        assert!(select(WASM_TARGET, Some(&source), Some("bad"), Some("false")).is_err());
        assert!(select(WASM_TARGET, Some(&source), Some(&content), Some("0")).is_err());
        assert_eq!(
            select(WASM_TARGET, Some(&source), Some(&content), Some("false")).unwrap(),
            Identity {
                source,
                content,
                dirty: false
            }
        );
    }

    #[test]
    fn host_defaults_are_valid_and_visibly_dirty() {
        let identity = select("x86_64-pc-windows-msvc", None, None, None).unwrap();
        assert_eq!(identity.source, HOST_SOURCE);
        assert_eq!(identity.content, HOST_CONTENT);
        assert!(identity.dirty);
    }
}
