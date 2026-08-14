#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

#[cfg(windows)]
fn main() {
    if std::env::args_os().nth(1).as_deref() == Some(std::ffi::OsStr::new("--focus-existing")) {
        if lament_mapper::window_focus::focus_existing_mapper() {
            lament_mapper::window_focus::write_helper_output("OK: LamentMapper window focused.\n");
        } else {
            lament_mapper::window_focus::write_helper_output("ERROR: LamentMapper window unavailable.\n");
        }
        return;
    }

    let runtime_dir = lament_mapper::runtime_dir();
    #[cfg(debug_assertions)]
    eprintln!(
        "LamentMapper debug build starting. Runtime log: {}",
        runtime_dir.join("logs").display()
    );
    let _logger = match lament_mapper::logging::initialize(&runtime_dir) {
        Ok(handle) => Some(handle),
        Err(error) => {
            eprintln!("LamentMapper logging could not start: {error}");
            None
        }
    };
    log::info!("LamentMapper starting");
    if let Err(error) = app::run(runtime_dir) {
        log::error!("application failed: {error}");
        eprintln!("LamentMapper failed: {error}");
    }
    log::info!("LamentMapper shut down cleanly");
    #[cfg(debug_assertions)]
    eprintln!("LamentMapper debug build shut down cleanly.");
}

#[cfg(windows)]
mod app;

#[cfg(not(windows))]
fn main() {
    eprintln!("LamentMapper currently supports Windows 10/11 x64 only.");
}
