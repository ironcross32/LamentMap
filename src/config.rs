use serde::{Deserialize, Serialize};
use std::fs::{self, File};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use thiserror::Error;

pub const CONFIG_VERSION: u32 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum FeedbackMode {
    Speech,
    #[default]
    SpeechAndSounds,
    Sounds,
}

impl FeedbackMode {
    pub const fn uses_speech(self) -> bool {
        matches!(self, Self::Speech | Self::SpeechAndSounds)
    }

    pub const fn uses_sounds(self) -> bool {
        matches!(self, Self::SpeechAndSounds | Self::Sounds)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct FeedbackConfig {
    pub mode: FeedbackMode,
    pub announce_directions: bool,
    pub new_map_alert: bool,
}

impl Default for FeedbackConfig {
    fn default() -> Self {
        Self {
            mode: FeedbackMode::SpeechAndSounds,
            announce_directions: true,
            new_map_alert: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    pub version: u32,
    pub feedback: FeedbackConfig,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            version: CONFIG_VERSION,
            feedback: FeedbackConfig::default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConfigRecovery {
    Existing,
    Created,
    Repaired { backup: PathBuf },
}

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("configuration I/O error: {0}")]
    Io(#[from] io::Error),
    #[error("configuration serialization failed: {0}")]
    Serialize(#[from] toml::ser::Error),
}

pub fn load_or_repair(path: &Path) -> Result<(Config, ConfigRecovery), ConfigError> {
    match fs::read_to_string(path) {
        Ok(contents) => match toml::from_str::<Config>(&contents) {
            Ok(config) if config.version == CONFIG_VERSION => Ok((config, ConfigRecovery::Existing)),
            _ => {
                let backup = next_backup_path(path);
                fs::rename(path, &backup)?;
                let config = Config::default();
                save_atomic(path, &config)?;
                Ok((config, ConfigRecovery::Repaired { backup }))
            }
        },
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            let config = Config::default();
            save_atomic(path, &config)?;
            Ok((config, ConfigRecovery::Created))
        }
        Err(error) => Err(error.into()),
    }
}

pub fn save_atomic(path: &Path, config: &Config) -> Result<(), ConfigError> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)?;
    let stem = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("config.toml");
    let mut attempt = 0u32;
    let temporary = loop {
        let candidate = parent.join(format!(".{stem}.tmp.{}.{}", std::process::id(), attempt));
        match File::options().write(true).create_new(true).open(&candidate) {
            Ok(mut file) => {
                let text = toml::to_string_pretty(config)?;
                file.write_all(text.as_bytes())?;
                file.sync_all()?;
                break candidate;
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => attempt += 1,
            Err(error) => return Err(error.into()),
        }
    };
    if let Err(error) = replace_file(&temporary, path) {
        let _ = fs::remove_file(&temporary);
        return Err(error.into());
    }
    Ok(())
}

fn next_backup_path(path: &Path) -> PathBuf {
    let base = PathBuf::from(format!("{}.bak", path.display()));
    if !base.exists() {
        return base;
    }
    for number in 1u32.. {
        let candidate = PathBuf::from(format!("{}.bak.{number}", path.display()));
        if !candidate.exists() {
            return candidate;
        }
    }
    unreachable!()
}

#[cfg(windows)]
fn replace_file(from: &Path, to: &Path) -> io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{
        MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH, MoveFileExW,
    };
    let from: Vec<u16> = from.as_os_str().encode_wide().chain(Some(0)).collect();
    let to: Vec<u16> = to.as_os_str().encode_wide().chain(Some(0)).collect();
    let result = unsafe {
        MoveFileExW(
            from.as_ptr(),
            to.as_ptr(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        )
    };
    if result == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[cfg(not(windows))]
fn replace_file(from: &Path, to: &Path) -> io::Result<()> {
    fs::rename(from, to)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn creates_defaults_and_accepts_partial_known_config() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("config.toml");
        let (config, recovery) = load_or_repair(&path).unwrap();
        assert_eq!(config, Config::default());
        assert_eq!(recovery, ConfigRecovery::Created);
        fs::write(&path, "version = 1\n[feedback]\nmode = \"speech\"\n").unwrap();
        let (config, recovery) = load_or_repair(&path).unwrap();
        assert_eq!(config.feedback.mode, FeedbackMode::Speech);
        assert!(config.feedback.announce_directions);
        assert_eq!(recovery, ConfigRecovery::Existing);
    }

    #[test]
    fn rotates_invalid_files_without_overwriting_backups() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("config.toml");
        fs::write(&path, "unknown = true").unwrap();
        fs::write(directory.path().join("config.toml.bak"), "older").unwrap();
        let (_, recovery) = load_or_repair(&path).unwrap();
        assert_eq!(
            recovery,
            ConfigRecovery::Repaired {
                backup: directory.path().join("config.toml.bak.1")
            }
        );
        assert_eq!(
            fs::read_to_string(directory.path().join("config.toml.bak")).unwrap(),
            "older"
        );
    }

    #[test]
    fn rejects_unsupported_version_unknown_fields_and_values() {
        for invalid in [
            "version = 2",
            "version = 1\nextra = true",
            "version = 1\n[feedback]\nmode = \"none\"",
        ] {
            let directory = tempfile::tempdir().unwrap();
            let path = directory.path().join("config.toml");
            fs::write(&path, invalid).unwrap();
            let (config, recovery) = load_or_repair(&path).unwrap();
            assert_eq!(config, Config::default());
            assert!(matches!(recovery, ConfigRecovery::Repaired { .. }));
        }
    }
}
