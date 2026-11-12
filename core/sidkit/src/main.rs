use std::env;
use std::fmt::Write;
use std::fs;
use std::path::PathBuf;
use std::process;

use sha2::{Digest, Sha256};

/// The shared volume from lab 3 is mounted here inside the container.
const DEFAULT_DATA_DIR: &str = "/data";
const SEED_FILE: &str = "seed.txt";
const KEY_FILE: &str = "sidkit.key";

/// Hashes the seed with SHA-256 and returns the 32-byte digest as 64 lowercase hex digits.
fn generate_key(seed: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    let digest = hasher.finalize();
    digest.iter().fold(String::with_capacity(64), |mut hex, b| {
        // Writing into a String cannot fail.
        let _ = write!(hex, "{b:02x}");
        hex
    })
}

/// Where the seed for the key comes from.
trait DataSource {
    fn fetch(&self) -> String;
}

/// Real source: the seed file in the shared volume from lab 3.
struct VolumeSeed {
    path: PathBuf,
}

impl DataSource for VolumeSeed {
    fn fetch(&self) -> String {
        // A missing or unreadable file is treated like an empty answer.
        fs::read_to_string(&self.path).unwrap_or_default()
    }
}

/// Builds the key from whatever the source returns. An empty or blank answer
/// gives an empty string instead of the hash of "", which anyone could predict.
fn generate_key_from_source(source: &dyn DataSource) -> String {
    let seed = source.fetch();
    let seed = seed.trim();
    if seed.is_empty() {
        return String::new();
    }
    generate_key(seed)
}

fn main() {
    let data_dir =
        PathBuf::from(env::var("SIDKIT_DATA_DIR").unwrap_or_else(|_| DEFAULT_DATA_DIR.to_string()));
    let source = VolumeSeed {
        path: data_dir.join(SEED_FILE),
    };

    let key = generate_key_from_source(&source);
    if key.is_empty() {
        eprintln!("Сід у {} порожній або відсутній", source.path.display());
        process::exit(1);
    }

    let key_path = data_dir.join(KEY_FILE);
    if let Err(err) = fs::write(&key_path, format!("{key}\n")) {
        eprintln!("Не вдалося записати {}: {err}", key_path.display());
        process::exit(1);
    }

    println!("Ключ відмички: {key}");
    println!("Записано у {}", key_path.display());
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Seed for variant 0 (N = 12, 12 % 4 = 0).
    const SEED: &str = "techno-b7-alpha";

    /// Stands in for the volume: returns a fixed answer and touches no file or network.
    struct MockSource {
        response: &'static str,
    }

    impl DataSource for MockSource {
        fn fetch(&self) -> String {
            self.response.to_string()
        }
    }

    #[test]
    fn generate_key_is_deterministic() {
        assert_eq!(generate_key(SEED), generate_key(SEED));
    }

    #[test]
    fn generate_key_differs_for_different_seed() {
        assert_ne!(
            generate_key("techno-b7-alpha"),
            generate_key("techno-b7-beta")
        );
    }

    #[test]
    fn generate_key_matches_sha256_test_vector() {
        // Known SHA-256 of "abc" from FIPS 180-2.
        assert_eq!(
            generate_key("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn generate_key_is_64_lowercase_hex_digits() {
        let key = generate_key(SEED);
        assert_eq!(key.len(), 64);
        assert!(key
            .chars()
            .all(|c| c.is_ascii_digit() || ('a'..='f').contains(&c)));
    }

    // Success: the mock returns a valid seed, and the key is the hash of exactly that seed.
    #[test]
    fn generate_key_from_source_uses_mock_seed() {
        let mock = MockSource {
            response: "mock-seed-0xC1D",
        };
        assert_eq!(
            generate_key_from_source(&mock),
            generate_key("mock-seed-0xC1D")
        );
    }

    // Success: a seed read from a file ends with a newline, which must not change the key.
    #[test]
    fn generate_key_from_source_ignores_trailing_newline() {
        let mock = MockSource {
            response: "techno-b7-alpha\n",
        };
        assert_eq!(generate_key_from_source(&mock), generate_key(SEED));
    }

    // Error: an empty answer gives no key rather than the hash of "".
    #[test]
    fn generate_key_from_source_rejects_empty_response() {
        let mock = MockSource { response: "" };
        assert_eq!(generate_key_from_source(&mock), "");
    }

    // Error: an answer of only whitespace is treated like an empty one.
    #[test]
    fn generate_key_from_source_rejects_blank_response() {
        let mock = MockSource { response: " \n\t" };
        assert_eq!(generate_key_from_source(&mock), "");
    }
}
