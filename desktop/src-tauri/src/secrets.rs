//! Storage and forwarding of AI provider API keys.
//!
//! Provider keys are the credentials the embedded Crystalline sidecar needs to
//! call model providers (Anthropic, OpenAI, …). They are *only* ever stored in
//! the OS keychain (macOS Keychain, Windows Credential Manager, or the Linux
//! Secret Service), never in config files, `sidecar.toml`, the app bundle, or
//! logs.
//!
//! The mapping from provider to the conventional environment variable the
//! sidecar expects is a pure function (`Provider::env_var`), and key access is
//! behind the [`KeyStore`] trait so the mode gate and the mapping are testable
//! without touching a real OS keychain.

use anyhow::Result;

/// OS keychain service under which provider keys are grouped.
///
/// Matches the Tauri bundle identifier (`com.facet.desktop`); each provider is
/// a separate account under this service.
const SERVICE: &str = "com.facet.desktop";

/// A model provider the embedded sidecar may need a key for.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Provider {
    Anthropic,
    OpenAI,
    Google,
    Groq,
    Mistral,
    OpenRouter,
}

impl Provider {
    /// Every supported provider, in display order.
    pub const ALL: [Provider; 6] = [
        Provider::Anthropic,
        Provider::OpenAI,
        Provider::Google,
        Provider::Groq,
        Provider::Mistral,
        Provider::OpenRouter,
    ];

    /// Stable machine identifier, also the keychain account name.
    pub fn id(self) -> &'static str {
        match self {
            Provider::Anthropic => "anthropic",
            Provider::OpenAI => "openai",
            Provider::Google => "google",
            Provider::Groq => "groq",
            Provider::Mistral => "mistral",
            Provider::OpenRouter => "openrouter",
        }
    }

    /// Conventional environment variable the sidecar reads for this provider.
    ///
    /// Pure mapping, unit-tested so a typo here cannot silently break key
    /// forwarding.
    pub fn env_var(self) -> &'static str {
        match self {
            Provider::Anthropic => "ANTHROPIC_API_KEY",
            Provider::OpenAI => "OPENAI_API_KEY",
            Provider::Google => "GOOGLE_API_KEY",
            Provider::Groq => "GROQ_API_KEY",
            Provider::Mistral => "MISTRAL_API_KEY",
            Provider::OpenRouter => "OPENROUTER_API_KEY",
        }
    }

    /// Resolve a provider from its stable id.
    pub fn from_id(id: &str) -> Option<Provider> {
        Provider::ALL.into_iter().find(|p| p.id() == id)
    }
}

/// Abstraction over the platform keychain so forwarding can be tested with an
/// in-memory store instead of a real OS keychain.
pub trait KeyStore {
    /// The stored key for a provider, if one is configured.
    fn get(&self, provider: Provider) -> Result<Option<String>>;
    /// Store (or replace) the key for a provider.
    fn set(&self, provider: Provider, value: &str) -> Result<()>;
    /// Remove the key for a provider.
    fn delete(&self, provider: Provider) -> Result<()>;
}

/// The production store backed by the OS keychain via the `keyring` crate.
pub struct KeyringStore;

impl KeyStore for KeyringStore {
    fn get(&self, provider: Provider) -> Result<Option<String>> {
        match keyring::Entry::new(SERVICE, provider.id()) {
            Ok(entry) => match entry.get_password() {
                Ok(value) => Ok(Some(value)),
                Err(keyring::Error::NoEntry) => Ok(None),
                Err(e) => Err(anyhow::anyhow!("keychain read failed: {}", e)),
            },
            Err(e) => Err(anyhow::anyhow!("keychain unavailable: {}", e)),
        }
    }

    fn set(&self, provider: Provider, value: &str) -> Result<()> {
        keyring::Entry::new(SERVICE, provider.id())?
            .set_password(value)
            .map_err(|e| anyhow::anyhow!("keychain write failed: {}", e))
    }

    fn delete(&self, provider: Provider) -> Result<()> {
        let entry = keyring::Entry::new(SERVICE, provider.id())?;
        match entry.delete_credential() {
            Ok(()) => Ok(()),
            Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(anyhow::anyhow!("keychain delete failed: {}", e)),
        }
    }
}

/// Ids of the providers that currently have a key configured.
///
/// Returns names only — never secret material — so it is safe to hand to the
/// frontend.
pub fn configured_providers(store: &dyn KeyStore) -> Vec<&'static str> {
    Provider::ALL
        .into_iter()
        .filter(|p| match store.get(*p) {
            Ok(Some(value)) => !value.is_empty(),
            Ok(None) => false,
            Err(_) => false,
        })
        .map(Provider::id)
        .collect()
}

/// `(env var, value)` pairs for every configured provider, ready to be set on
/// the sidecar child process.
///
/// A provider that cannot be read is skipped with a warning that names the
/// provider only — the secret value itself is never passed to `log::`.
pub fn forwarded_env(store: &dyn KeyStore) -> Vec<(String, String)> {
    Provider::ALL
        .into_iter()
        .filter_map(|provider| match store.get(provider) {
            Ok(Some(value)) if !value.is_empty() => {
                Some((provider.env_var().to_string(), value))
            }
            Ok(_) => None,
            Err(_) => {
                log::warn!("Could not read the {} API key from the keychain", provider.id());
                None
            }
        })
        .collect()
}

/// In-memory [`KeyStore`] shared by the test modules in this crate.
#[cfg(test)]
pub(crate) mod test_support {
    use super::{KeyStore, Provider};
    use anyhow::Result;
    use std::cell::RefCell;
    use std::collections::HashMap;

    pub struct FakeStore(RefCell<HashMap<Provider, String>>);

    impl FakeStore {
        pub fn with(entries: &[(&str, &str)]) -> Self {
            let mut map = HashMap::new();
            for (id, value) in entries {
                map.insert(Provider::from_id(id).unwrap(), value.to_string());
            }
            Self(RefCell::new(map))
        }
    }

    impl KeyStore for FakeStore {
        fn get(&self, provider: Provider) -> Result<Option<String>> {
            Ok(self.0.borrow().get(&provider).cloned())
        }
        fn set(&self, provider: Provider, value: &str) -> Result<()> {
            self.0.borrow_mut().insert(provider, value.to_string());
            Ok(())
        }
        fn delete(&self, provider: Provider) -> Result<()> {
            self.0.borrow_mut().remove(&provider);
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_env_mapping_is_conventional() {
        let expected = [
            (Provider::Anthropic, "ANTHROPIC_API_KEY"),
            (Provider::OpenAI, "OPENAI_API_KEY"),
            (Provider::Google, "GOOGLE_API_KEY"),
            (Provider::Groq, "GROQ_API_KEY"),
            (Provider::Mistral, "MISTRAL_API_KEY"),
            (Provider::OpenRouter, "OPENROUTER_API_KEY"),
        ];
        for (provider, env_var) in expected {
            assert_eq!(provider.env_var(), env_var, "{}", provider.id());
        }
    }

    #[test]
    fn from_id_roundtrips_every_provider() {
        for provider in Provider::ALL {
            assert_eq!(Provider::from_id(provider.id()), Some(provider));
        }
        assert_eq!(Provider::from_id("nope"), None);
    }

    #[test]
    fn configured_providers_lists_names_only() {
        let store = test_support::FakeStore::with(&[("anthropic", "sk-fake"), ("openai", "sk-2")]);
        let mut ids = configured_providers(&store);
        ids.sort_unstable();
        assert_eq!(ids, vec!["anthropic", "openai"]);
    }

    #[test]
    fn forwarded_env_includes_only_configured_non_empty_keys() {
        let store =
            test_support::FakeStore::with(&[("anthropic", "sk-fake"), ("openai", "sk-2")]);
        let env = forwarded_env(&store);
        let mut by_name: std::collections::HashMap<&str, &str> = env
            .iter()
            .map(|(k, v)| (k.as_str(), v.as_str()))
            .collect();
        assert_eq!(by_name.get("ANTHROPIC_API_KEY"), Some(&"sk-fake"));
        assert_eq!(by_name.get("OPENAI_API_KEY"), Some(&"sk-2"));
        assert!(!by_name.contains_key("GROQ_API_KEY"));
        by_name.remove("ANTHROPIC_API_KEY");
        by_name.remove("OPENAI_API_KEY");
        assert!(by_name.is_empty(), "unexpected extra env vars: {:?}", by_name);
    }
}
