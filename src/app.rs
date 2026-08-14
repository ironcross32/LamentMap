use lament_mapper::audio::AudioEngine;
use lament_mapper::config::{Config, ConfigRecovery, FeedbackMode, load_or_repair, save_atomic};
use lament_mapper::feedback::{Feedback, SoundOutput, SpeechOutput};
use lament_mapper::map_input::{
    HostKeyAction, KeyModifiers, classify_key, dimensions_readout, terrain_readout,
};
use lament_mapper::model::Map;
use lament_mapper::navigation::{Cursor, MoveResult, announcement};
use lament_mapper::prism::Prism;
use lament_mapper::protocol::parse_line;
use lament_mapper::transport::{InputTransport, TransportEvent};
use lament_mapper::window_focus;
use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::{Duration, Instant};
use windows_sys::Win32::Foundation::INVALID_HANDLE_VALUE;
use windows_sys::Win32::Storage::FileSystem::{FILE_TYPE_PIPE, GetFileType};
use windows_sys::Win32::System::Console::{GetStdHandle, STD_INPUT_HANDLE};
use windows_sys::Win32::UI::WindowsAndMessaging::{SW_SHOWNOACTIVATE, ShowWindow};
use wxdragon::accessible::{AccRole, AccState, AccStatus, AccessibleImpl};
use wxdragon::prelude::*;

const MENU_PREFERENCES: i32 = ID_HIGHEST + 101;
const MENU_README: i32 = ID_HIGHEST + 102;
const SPEECH_LABEL: &str = "Speech";
const SPEECH_AND_SOUNDS_LABEL: &str = "Speech and sounds";
const SOUNDS_LABEL: &str = "Sounds";
const DIRECTIONS_LABEL: &str = "Announce directions relative to the player";
const NEW_MAP_ALERT_LABEL: &str = "Play the new-map alert";
const OK_LABEL: &str = "OK";
const CANCEL_LABEL: &str = "Cancel";

struct PrismSpeech(Prism);

/// The focus host is the only native accessibility object for the map area.
/// It deliberately exposes no wxGrid children; map semantics are output by Prism.
struct MapHostAccessible;

impl AccessibleImpl for MapHostAccessible {
    fn get_child(&self, _child_id: i32) -> (AccStatus, Option<Accessible>) {
        (AccStatus::InvalidArg, None)
    }

    fn get_role(&self, child_id: i32) -> (AccStatus, AccRole) {
        if child_id == 0 {
            (AccStatus::Ok, AccRole::Client)
        } else {
            (AccStatus::InvalidArg, AccRole::None)
        }
    }

    fn get_state(&self, child_id: i32) -> (AccStatus, AccState) {
        if child_id == 0 {
            (AccStatus::Ok, AccState::empty())
        } else {
            (AccStatus::InvalidArg, AccState::empty())
        }
    }

    fn get_name(&self, child_id: i32) -> (AccStatus, Option<String>) {
        if child_id == 0 {
            (AccStatus::Ok, Some("Wilderness map explorer".into()))
        } else {
            (AccStatus::InvalidArg, None)
        }
    }

    fn get_description(&self, child_id: i32) -> (AccStatus, Option<String>) {
        if child_id == 0 {
            (AccStatus::Ok, None)
        } else {
            (AccStatus::InvalidArg, None)
        }
    }

    fn get_value(&self, child_id: i32) -> (AccStatus, Option<String>) {
        self.get_description(child_id)
    }

    fn get_focus(&self) -> (AccStatus, i32, Option<Accessible>) {
        (AccStatus::Ok, 0, None)
    }
}

/// Supplies only an MSAA name and delegates every other property to the
/// control's native accessible object.
struct NameOnlyAccessible(String);

impl AccessibleImpl for NameOnlyAccessible {
    fn get_child_count(&self) -> (AccStatus, i32) {
        (AccStatus::NotImplemented, 0)
    }

    fn get_name(&self, child_id: i32) -> (AccStatus, Option<String>) {
        if child_id == 0 {
            (AccStatus::Ok, Some(self.0.clone()))
        } else {
            (AccStatus::NotImplemented, None)
        }
    }
}

fn set_accessible_name(widget: &dyn WxWidget, name: &str) {
    widget.set_accessible(Accessible::new(widget, NameOnlyAccessible(name.to_owned())));
}

impl SpeechOutput for PrismSpeech {
    fn output(&mut self, phrase: &str) -> Result<(), String> {
        self.0.send(phrase).map_err(|error| error.to_string())
    }
}

type AppFeedback = Feedback<PrismSpeech, AudioEngine>;

struct State {
    map: Option<Map>,
    cursor: Option<Cursor>,
    config: Config,
    config_path: PathBuf,
    feedback: AppFeedback,
    mudlet_process_id: Option<u32>,
    last_map: Option<Instant>,
    displayed_status: String,
}

pub fn run(runtime_dir: PathBuf) -> Result<(), Box<dyn std::error::Error>> {
    let config_path = runtime_dir.join("config.toml");
    let (config, recovery) = load_or_repair(&config_path)?;
    match recovery {
        ConfigRecovery::Existing => {}
        ConfigRecovery::Created => log::info!("created default configuration"),
        ConfigRecovery::Repaired { backup } => {
            log::warn!("repaired invalid configuration; backup is {}", backup.display());
        }
    }
    let feedback_mode = match config.feedback.mode {
        FeedbackMode::Speech => "speech",
        FeedbackMode::SpeechAndSounds => "speech_and_sounds",
        FeedbackMode::Sounds => "sounds",
    };
    log::info!("loaded feedback mode: {feedback_mode}");

    wxdragon::main(move |app| {
        let Some(checker) = SingleInstanceChecker::new("LamentMapper.bscross32.v1", None) else {
            log::error!("single-instance checker could not be created");
            app.exit_main_loop();
            return;
        };
        if checker.is_another_running() {
            log::info!("another instance is running; exiting without activation");
            app.exit_main_loop();
            return;
        }
        let _checker = Box::leak(Box::new(checker));

        let frame = Frame::builder()
            .with_title("LamentMapper")
            .with_size(Size::new(760, 720))
            .build();
        app.set_top_window(&frame);

        let host = Panel::builder(&frame).build();
        host.set_name("Wilderness map explorer");
        host.set_can_focus(true);
        host.set_accessible(Accessible::new(&host, MapHostAccessible));
        let grid = Grid::builder(&host).build();
        grid.create_grid(1, 1, GridSelectionMode::None);
        configure_grid(&grid);
        grid.set_can_focus(false);

        let host_sizer = BoxSizer::builder(Orientation::Vertical).build();
        host_sizer.add(&grid, 1, SizerFlag::Expand, 0);
        host.set_sizer(host_sizer, true);
        let frame_sizer = BoxSizer::builder(Orientation::Vertical).build();
        frame_sizer.add(&host, 1, SizerFlag::Expand, 0);
        frame.set_sizer(frame_sizer, true);

        let status = StatusBar::builder(&frame)
            .with_fields_count(1)
            .add_initial_text(0, "Ready")
            .build();
        frame.set_existing_status_bar(Some(&status));
        install_menu(&frame);

        let prism_path = runtime_dir.join("prism.dll");
        let prism = match Prism::load(&prism_path) {
            Ok(prism) => {
                log::info!("Prism backend acquired: {}", prism.backend_name());
                prism
            }
            Err(error) => {
                log::error!("required Prism startup failed: {error}");
                MessageDialog::builder(
                    &frame,
                    &format!(
                        "LamentMapper cannot start because its required screen-reader component is unavailable.\n\n\
                         Make sure prism.dll is installed beside LamentMapper.exe.\n\n\
                         Expected location:\n{}\n\nError:\n{error}",
                        prism_path.display()
                    ),
                    "LamentMapper cannot start",
                )
                .with_style(MessageDialogStyle::OK | MessageDialogStyle::IconError)
                .build()
                .show_modal();
                frame.destroy();
                app.exit_main_loop();
                return;
            }
        };
        let audio = AudioEngine::load(&runtime_dir.join("sounds.pack"));
        let feedback = Feedback {
            mode: config.feedback.mode,
            speech: PrismSpeech(prism),
            audio,
        };
        let managed_stdin = stdin_is_pipe();
        let mudlet_process_id = managed_stdin.then(window_focus::parent_process_id).flatten();
        if let Some(process_id) = mudlet_process_id {
            log::info!("recorded managed Mudlet parent process {process_id}");
        } else if managed_stdin {
            log::warn!("managed stdin detected, but its parent process could not be determined");
        }
        let state = Rc::new(RefCell::new(State {
            map: None,
            cursor: None,
            config,
            config_path,
            feedback,
            mudlet_process_id,
            last_map: None,
            displayed_status: "Ready".into(),
        }));
        let transport = if managed_stdin {
            log::info!("managed stdin pipe detected");
            Some(Rc::new(InputTransport::spawn(std::io::stdin(), 8)))
        } else {
            log::info!("no managed stdin pipe detected; remaining open in standalone idle mode");
            None
        };

        bind_keyboard(&host, &grid, &state);
        bind_menu(&frame, &host, &state, &runtime_dir);
        let frame_for_close = frame;
        frame.on_close(move |event| {
            log::info!("main window close requested");
            event.skip(true);
        });
        let host_for_activate = host;
        let state_for_activate = state.clone();
        frame.on_activate(move |event| {
            if let WindowEventData::Activate(event) = event
                && event.is_active()
            {
                host_for_activate.set_focus();
                let mut state = state_for_activate.borrow_mut();
                let phrase = match (&state.map, state.cursor) {
                    (Some(map), Some(cursor)) => {
                        announcement(map, cursor, state.config.feedback.announce_directions)
                    }
                    _ => "Waiting for a wilderness map.".into(),
                };
                state.feedback.focus(&phrase);
            }
        });

        let timer = Box::leak(Box::new(Timer::new(&frame)));
        let state_for_tick = state.clone();
        let transport_for_tick = transport.clone();
        timer.on_tick(move |_| {
            while let Some(transport) = &transport_for_tick {
                match transport.try_recv() {
                    Ok(TransportEvent::Line(line)) => match parse_line(&line) {
                        Ok(map) => accept_map(&grid, &state_for_tick, map),
                        Err(error) => log::warn!("discarded map input: {error}"),
                    },
                    Ok(TransportEvent::Error(error)) => log::warn!("stdin transport error: {error}"),
                    Ok(TransportEvent::Eof) => {
                        log::info!("stdin reached EOF; closing");
                        frame_for_close.close(true);
                        break;
                    }
                    Err(
                        crossbeam_channel::TryRecvError::Empty
                        | crossbeam_channel::TryRecvError::Disconnected,
                    ) => break,
                }
            }
            let mut state = state_for_tick.borrow_mut();
            let updated_status = status_text(state.last_map);
            if state.displayed_status != updated_status {
                status.set_status_text(&updated_status, 0);
                state.displayed_status = updated_status;
            }
        });
        timer.start(100, false);

        frame.centre();
        let native = frame.get_handle();
        if !native.is_null() {
            unsafe { ShowWindow(native, SW_SHOWNOACTIVATE) };
        } else {
            frame.show(true);
        }
        log::info!("native window created without requesting foreground activation");
    })?;
    Ok(())
}

fn stdin_is_pipe() -> bool {
    unsafe {
        let handle = GetStdHandle(STD_INPUT_HANDLE);
        !handle.is_null() && handle != INVALID_HANDLE_VALUE && GetFileType(handle) == FILE_TYPE_PIPE
    }
}

fn configure_grid(grid: &Grid) {
    grid.enable_editing(false);
    grid.set_row_label_size(0);
    grid.set_col_label_size(0);
    grid.set_default_row_size(34, true);
    grid.set_default_col_size(42, true);
    grid.disable_drag_col_move();
    grid.disable_drag_col_size();
    grid.disable_drag_row_size();
    grid.disable_drag_grid_size();
    grid.set_tab_behaviour(TabBehaviour::Stop);
    grid.set_cell_highlight_pen_width(0);
    grid.set_cell_highlight_ro_pen_width(0);
    if let Some(font) = Font::new_with_details(
        14,
        FontFamily::Teletype.as_i32(),
        FontStyle::Normal.as_i32(),
        FontWeight::Normal.as_i32(),
        false,
        "Consolas",
    ) {
        grid.set_default_cell_font(&font);
    }
}

fn install_menu(frame: &Frame) {
    let file = Menu::builder().build();
    file.append(
        MENU_PREFERENCES,
        "&Preferences...\tCtrl+,",
        "Configure map feedback",
        ItemKind::Normal,
    );
    file.append_separator();
    file.append(ID_EXIT, "E&xit\tAlt+F4", "Exit LamentMapper", ItemKind::Normal);
    let help = Menu::builder().build();
    help.append(
        MENU_README,
        "&View guide",
        "Open the bundled LamentMapper guide",
        ItemKind::Normal,
    );
    frame.set_menu_bar(
        MenuBar::builder()
            .append(file, "&File")
            .append(help, "&Help")
            .build(),
    );
}

fn bind_keyboard(host: &Panel, grid: &Grid, state: &Rc<RefCell<State>>) {
    let state = state.clone();
    let grid = *grid;
    host.on_key_down(move |event| {
        let WindowEventData::Keyboard(keyboard) = &event else {
            event.skip(true);
            return;
        };
        let key_action = classify_key(
            keyboard.get_key_code().unwrap_or_default(),
            KeyModifiers {
                control: keyboard.control_down(),
                shift: keyboard.shift_down(),
                alt: keyboard.alt_down(),
                meta: keyboard.meta_down(),
            },
        );
        if key_action == HostKeyAction::PassThrough {
            event.skip(true);
            return;
        }

        event.skip(false);
        grid.clear_selection();
        let mut state = state.borrow_mut();
        match key_action {
            HostKeyAction::Consume | HostKeyAction::PassThrough => {}
            HostKeyAction::FocusMudlet => {
                let focused = state
                    .mudlet_process_id
                    .is_some_and(window_focus::focus_parent_window);
                if !focused {
                    state.feedback.explicit("Mudlet window unavailable.");
                }
            }
            HostKeyAction::TerrainReadout => {
                let phrase = terrain_readout(state.map.as_ref(), state.cursor);
                state.feedback.explicit(&phrase);
            }
            HostKeyAction::DimensionsReadout => {
                let phrase = dimensions_readout(state.map.as_ref());
                state.feedback.explicit(&phrase);
            }
            HostKeyAction::Navigate(action) => {
                let Some(map) = state.map.clone() else {
                    return;
                };
                let previous_cursor = state.cursor;
                let mut cursor = previous_cursor.unwrap_or_else(|| Cursor::centered(&map));
                let result = cursor.apply(&map, action);
                state.cursor = Some(cursor);
                let cell = map.cell(cursor.row, cursor.column).expect("valid cursor");
                let phrase = if result == MoveResult::Boundary {
                    "Map boundary.".to_owned()
                } else {
                    announcement(&map, cursor, state.config.feedback.announce_directions)
                };
                render_visual_cursor(&grid, previous_cursor, cursor);
                grid.make_cell_visible(cursor.row as i32, cursor.column as i32);
                state.feedback.navigation(result, cell.kind, &phrase);
            }
        }
    });
}

fn bind_menu(frame: &Frame, host: &Panel, state: &Rc<RefCell<State>>, runtime_dir: &Path) {
    let state = state.clone();
    let runtime_dir = runtime_dir.to_owned();
    let frame_copy = *frame;
    let host_copy = *host;
    frame.on_menu(move |event| match event.get_id() {
        ID_EXIT => frame_copy.close(false),
        MENU_README => {
            let guide = runtime_dir.join("README.html");
            if !guide.is_file() {
                MessageDialog::builder(
                    &frame_copy,
                    "README.html was not found beside LamentMapper.exe.",
                    "Guide unavailable",
                )
                .with_style(MessageDialogStyle::OK | MessageDialogStyle::IconWarning)
                .build()
                .show_modal();
            } else {
                let target = format!("file:///{}", guide.to_string_lossy().replace('\\', "/"));
                if !launch_default_browser(&target, BrowserLaunchFlags::NewWindow) {
                    log::warn!("could not open bundled guide: {}", guide.display());
                }
            }
            host_copy.set_focus();
        }
        MENU_PREFERENCES => {
            let (current, complete) = {
                let state = state.borrow();
                (state.config.clone(), state.feedback.audio.is_complete())
            };
            if let Some(updated) = preferences(&frame_copy, &current, complete) {
                let mut state = state.borrow_mut();
                match save_atomic(&state.config_path, &updated) {
                    Ok(()) => {
                        state.feedback.mode = updated.feedback.mode;
                        state.config = updated;
                        log::info!("preferences saved");
                    }
                    Err(error) => {
                        log::error!("preferences could not be saved: {error}");
                        MessageDialog::builder(
                            &frame_copy,
                            &format!("Preferences could not be saved:\n{error}"),
                            "Save failed",
                        )
                        .with_style(MessageDialogStyle::OK | MessageDialogStyle::IconError)
                        .build()
                        .show_modal();
                    }
                }
            }
            host_copy.set_focus();
        }
        _ => event.skip(true),
    });
}

fn preferences(parent: &Frame, current: &Config, sounds_complete: bool) -> Option<Config> {
    let dialog = Dialog::builder(parent, "LamentMapper Preferences")
        .with_size(440, 330)
        .build();
    let group =
        StaticBoxSizerBuilder::new_with_label(Orientation::Vertical, &dialog, "Cursor feedback").build();
    let group_box = group
        .get_static_box()
        .expect("a labelled static-box sizer owns its static box");
    let speech = RadioButton::builder(&group_box)
        .with_label(SPEECH_LABEL)
        .first_in_group()
        .build();
    let both = RadioButton::builder(&group_box)
        .with_label(SPEECH_AND_SOUNDS_LABEL)
        .build();
    let sounds = RadioButton::builder(&group_box).with_label(SOUNDS_LABEL).build();
    match current.feedback.mode {
        FeedbackMode::Speech => speech.set_value(true),
        FeedbackMode::SpeechAndSounds => both.set_value(true),
        FeedbackMode::Sounds => sounds.set_value(true),
    }
    let directions = CheckBox::builder(&dialog)
        .with_label(DIRECTIONS_LABEL)
        .with_value(current.feedback.announce_directions)
        .build();
    let new_map = CheckBox::builder(&dialog)
        .with_label(NEW_MAP_ALERT_LABEL)
        .with_value(current.feedback.new_map_alert)
        .build();
    let ok = Button::builder(&dialog)
        .with_id(ID_OK)
        .with_label(OK_LABEL)
        .build();
    let cancel = Button::builder(&dialog)
        .with_id(ID_CANCEL)
        .with_label(CANCEL_LABEL)
        .build();
    for (control, label) in [
        (&speech as &dyn WxWidget, SPEECH_LABEL),
        (&both as &dyn WxWidget, SPEECH_AND_SOUNDS_LABEL),
        (&sounds as &dyn WxWidget, SOUNDS_LABEL),
        (&directions as &dyn WxWidget, DIRECTIONS_LABEL),
        (&new_map as &dyn WxWidget, NEW_MAP_ALERT_LABEL),
        (&ok as &dyn WxWidget, OK_LABEL),
        (&cancel as &dyn WxWidget, CANCEL_LABEL),
    ] {
        set_accessible_name(control, label);
    }

    let outer = BoxSizer::builder(Orientation::Vertical).build();
    group.add(&speech, 0, SizerFlag::All, 6);
    group.add(&both, 0, SizerFlag::All, 6);
    group.add(&sounds, 0, SizerFlag::All, 6);
    outer.add_sizer(&group, 0, SizerFlag::Expand | SizerFlag::All, 10);
    outer.add(&directions, 0, SizerFlag::All, 10);
    outer.add(&new_map, 0, SizerFlag::All, 10);
    let buttons = BoxSizer::builder(Orientation::Horizontal).build();
    buttons.add_stretch_spacer(1);
    buttons.add(&ok, 0, SizerFlag::All, 6);
    buttons.add(&cancel, 0, SizerFlag::All, 6);
    outer.add_sizer(&buttons, 0, SizerFlag::Expand | SizerFlag::All, 6);
    dialog.set_sizer(outer, true);
    dialog.set_affirmative_id(ID_OK);
    dialog.set_escape_id(ID_CANCEL);

    let dialog_ok = dialog;
    ok.on_click(move |_| dialog_ok.end_modal(ID_OK));
    let dialog_cancel = dialog;
    cancel.on_click(move |_| dialog_cancel.end_modal(ID_CANCEL));
    speech.set_focus();
    let accepted = dialog.show_modal() == ID_OK;
    let result = if accepted {
        let mut updated = current.clone();
        updated.feedback.mode = if speech.get_value() {
            FeedbackMode::Speech
        } else if both.get_value() {
            FeedbackMode::SpeechAndSounds
        } else {
            FeedbackMode::Sounds
        };
        updated.feedback.announce_directions = directions.get_value();
        updated.feedback.new_map_alert = new_map.get_value();
        if updated.feedback.mode == FeedbackMode::Sounds && !sounds_complete {
            MessageDialog::builder(
                parent,
                "The sound pack or audio output is incomplete. Sounds-only mode may be silent until it is restored.",
                "Sounds unavailable",
            )
            .with_style(MessageDialogStyle::OK | MessageDialogStyle::IconWarning)
            .build()
            .show_modal();
        }
        Some(updated)
    } else {
        None
    };
    dialog.destroy();
    result
}

fn accept_map(grid: &Grid, state: &Rc<RefCell<State>>, map: Map) {
    resize_grid(grid, map.size as i32);
    for row in 0..map.size {
        for column in 0..map.size {
            let cell = map.cell(row, column).expect("map dimensions validated");
            grid.set_cell_value(row as i32, column as i32, &cell.token);
            grid.set_read_only(row as i32, column as i32, true);
            grid.set_cell_overflow(row as i32, column as i32, false);
            if let Some(font) = map_font(false) {
                grid.set_cell_font(row as i32, column as i32, &font);
            }
            let style = cell.styles[0];
            grid.set_cell_text_colour(
                row as i32,
                column as i32,
                &Colour::rgb(style.foreground.r, style.foreground.g, style.foreground.b),
            );
            grid.set_cell_background_colour(
                row as i32,
                column as i32,
                &Colour::rgb(style.background.r, style.background.g, style.background.b),
            );
        }
    }
    let cursor = Cursor::centered(&map);
    render_visual_cursor(grid, None, cursor);
    grid.make_cell_visible(cursor.row as i32, cursor.column as i32);
    grid.refresh(false, None);
    let mut state = state.borrow_mut();
    state.cursor = Some(cursor);
    state.last_map = Some(Instant::now());
    log::info!(
        "accepted {}x{} map, sequence {}",
        map.size,
        map.size,
        map.sequence
    );
    let new_map_alert = state.config.feedback.new_map_alert;
    state.feedback.new_map(new_map_alert);
    state.map = Some(map);
}

fn map_font(highlighted: bool) -> Option<Font> {
    Font::new_with_details(
        14,
        FontFamily::Teletype.as_i32(),
        FontStyle::Normal.as_i32(),
        if highlighted {
            FontWeight::Bold.as_i32()
        } else {
            FontWeight::Normal.as_i32()
        },
        highlighted,
        "Consolas",
    )
}

fn render_visual_cursor(grid: &Grid, previous: Option<Cursor>, current: Cursor) {
    if let Some(previous) = previous
        && previous != current
        && let Some(font) = map_font(false)
    {
        grid.set_cell_font(previous.row as i32, previous.column as i32, &font);
    }
    if let Some(font) = map_font(true) {
        grid.set_cell_font(current.row as i32, current.column as i32, &font);
    }
    grid.clear_selection();
    grid.refresh(false, None);
}

fn resize_grid(grid: &Grid, size: i32) {
    let rows = grid.get_number_rows();
    if rows < size {
        grid.append_rows(size - rows, false);
    } else if rows > size {
        grid.delete_rows(size, rows - size, false);
    }
    let columns = grid.get_number_cols();
    if columns < size {
        grid.append_cols(size - columns, false);
    } else if columns > size {
        grid.delete_cols(size, columns - size, false);
    }
    grid.set_default_row_size(34, true);
    grid.set_default_col_size(42, true);
}

fn status_text(last_map: Option<Instant>) -> String {
    let Some(last_map) = last_map else {
        return "Ready".into();
    };
    let elapsed = last_map.elapsed();
    if elapsed < Duration::from_secs(2) {
        "Map received just now".into()
    } else if elapsed < Duration::from_secs(60) {
        format!("Map received {} seconds ago", elapsed.as_secs())
    } else {
        let minutes = elapsed.as_secs() / 60;
        format!(
            "Map received {minutes} minute{} ago",
            if minutes == 1 { "" } else { "s" }
        )
    }
}

#[cfg(test)]
mod accessibility_tests {
    use super::*;

    #[test]
    fn name_only_accessible_delegates_child_count() {
        let accessible = NameOnlyAccessible("Speech".into());
        assert_eq!(accessible.get_child_count(), (AccStatus::NotImplemented, 0));
    }

    #[test]
    fn name_only_accessible_names_only_the_control_itself() {
        let accessible = NameOnlyAccessible("Speech and sounds".into());
        assert_eq!(
            accessible.get_name(0),
            (AccStatus::Ok, Some("Speech and sounds".into()))
        );
        assert_eq!(accessible.get_name(1), (AccStatus::NotImplemented, None));
    }
}
