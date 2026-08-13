pub mod audio;
pub mod config;
pub mod feedback;
pub mod logging;
pub mod model;
pub mod navigation;
pub mod prism;
pub mod protocol;
pub mod transport;

use std::path::PathBuf;

pub fn runtime_dir() -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|path| path.parent().map(ToOwned::to_owned))
        .or_else(|| std::env::current_dir().ok())
        .unwrap_or_else(|| PathBuf::from("."))
}
