use flexi_logger::{Cleanup, Criterion, FileSpec, Logger, LoggerHandle, Naming};
use std::path::Path;

pub fn initialize(runtime_dir: &Path) -> Result<LoggerHandle, flexi_logger::FlexiLoggerError> {
    let log_dir = runtime_dir.join("logs");
    Logger::try_with_str("info")?
        .log_to_file(
            FileSpec::default()
                .directory(log_dir)
                .basename("LamentMapper")
                .suppress_timestamp(),
        )
        .rotate(
            Criterion::Size(1024 * 1024),
            Naming::Numbers,
            Cleanup::KeepLogFiles(5),
        )
        .append()
        .start()
}
