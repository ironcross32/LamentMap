use crate::menu::MenuCommand;
use crate::model::Map;
use crate::navigation::{
    Action, Cursor, DirectionStyle, automatic_route, relative_directions, road_topology,
};
use std::time::{Duration, Instant};

pub const KEY_ENTER: i32 = 13;
pub const KEY_ESCAPE: i32 = 27;
pub const KEY_SPACE: i32 = 32;
pub const KEY_COMMA: i32 = 44;
pub const KEY_D: i32 = 68;
pub const KEY_H: i32 = 72;
pub const KEY_M: i32 = 77;
pub const KEY_T: i32 = 84;
pub const KEY_HOME: i32 = 312;
pub const KEY_END: i32 = 313;
pub const KEY_LEFT: i32 = 314;
pub const KEY_UP: i32 = 315;
pub const KEY_RIGHT: i32 = 316;
pub const KEY_DOWN: i32 = 317;
pub const KEY_NUMPAD0: i32 = 324;
pub const KEY_NUMPAD1: i32 = 325;
pub const KEY_NUMPAD2: i32 = 326;
pub const KEY_NUMPAD3: i32 = 327;
pub const KEY_NUMPAD4: i32 = 328;
pub const KEY_NUMPAD5: i32 = 329;
pub const KEY_NUMPAD6: i32 = 330;
pub const KEY_NUMPAD7: i32 = 331;
pub const KEY_NUMPAD8: i32 = 332;
pub const KEY_NUMPAD9: i32 = 333;
pub const KEY_F10: i32 = 349;
pub const KEY_PAGE_UP: i32 = 366;
pub const KEY_PAGE_DOWN: i32 = 367;
pub const KEY_NUMPAD_ENTER: i32 = 370;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct KeyModifiers {
    pub control: bool,
    pub shift: bool,
    pub alt: bool,
    pub meta: bool,
}

impl KeyModifiers {
    const fn none(self) -> bool {
        !self.control && !self.shift && !self.alt && !self.meta
    }

    const fn control_only(self) -> bool {
        self.control && !self.shift && !self.alt && !self.meta
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HostKeyAction {
    Navigate(Action),
    TerrainReadout,
    DimensionsReadout,
    DirectionReadout,
    TerrainMenu,
    MoveRequest,
    CancelMove,
    FocusMudlet,
    PassThrough,
    Consume,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MovementRouteError {
    NoMap,
    PlayerPosition,
}

pub fn classify_key(key_code: i32, modifiers: KeyModifiers) -> HostKeyAction {
    if modifiers.alt {
        return HostKeyAction::PassThrough;
    }
    if modifiers.none() && key_code == KEY_F10 {
        return HostKeyAction::PassThrough;
    }
    if modifiers.control_only() && key_code == KEY_COMMA {
        return HostKeyAction::PassThrough;
    }
    if modifiers.control_only() && key_code == KEY_SPACE {
        return HostKeyAction::FocusMudlet;
    }
    if !modifiers.none() {
        return HostKeyAction::Consume;
    }
    match key_code {
        KEY_UP | KEY_NUMPAD8 => HostKeyAction::Navigate(Action::North),
        KEY_NUMPAD9 => HostKeyAction::Navigate(Action::Northeast),
        KEY_RIGHT | KEY_NUMPAD6 => HostKeyAction::Navigate(Action::East),
        KEY_NUMPAD3 => HostKeyAction::Navigate(Action::Southeast),
        KEY_DOWN | KEY_NUMPAD2 => HostKeyAction::Navigate(Action::South),
        KEY_NUMPAD1 => HostKeyAction::Navigate(Action::Southwest),
        KEY_LEFT | KEY_NUMPAD4 => HostKeyAction::Navigate(Action::West),
        KEY_NUMPAD7 => HostKeyAction::Navigate(Action::Northwest),
        KEY_SPACE | KEY_NUMPAD5 => HostKeyAction::Navigate(Action::Center),
        KEY_ENTER | KEY_NUMPAD_ENTER => HostKeyAction::TerrainReadout,
        KEY_D | KEY_NUMPAD0 => HostKeyAction::DimensionsReadout,
        KEY_H => HostKeyAction::DirectionReadout,
        KEY_T => HostKeyAction::TerrainMenu,
        KEY_M => HostKeyAction::MoveRequest,
        KEY_ESCAPE => HostKeyAction::CancelMove,
        _ => HostKeyAction::Consume,
    }
}

pub fn classify_menu_key(key_code: i32, modifiers: KeyModifiers) -> Option<MenuCommand> {
    if !modifiers.none() {
        return None;
    }
    Some(match key_code {
        KEY_UP | KEY_NUMPAD8 => MenuCommand::Up,
        KEY_DOWN | KEY_NUMPAD2 => MenuCommand::Down,
        KEY_HOME => MenuCommand::Home,
        KEY_END => MenuCommand::End,
        KEY_PAGE_UP => MenuCommand::PageUp,
        KEY_PAGE_DOWN => MenuCommand::PageDown,
        KEY_LEFT | KEY_NUMPAD4 => MenuCommand::PreviousValue,
        KEY_RIGHT | KEY_NUMPAD6 => MenuCommand::NextValue,
        KEY_ENTER | KEY_NUMPAD_ENTER => MenuCommand::Confirm,
        KEY_ESCAPE => MenuCommand::Dismiss,
        _ => return None,
    })
}

pub const DIRECTION_DOUBLE_TAP_WINDOW: Duration = Duration::from_millis(500);

#[derive(Debug, Default)]
pub struct DirectionTapTracker {
    last_press: Option<Instant>,
}

impl DirectionTapTracker {
    pub fn style_for_press(&mut self, now: Instant, preferred: DirectionStyle) -> DirectionStyle {
        if self.last_press.is_some_and(|last_press| {
            now.checked_duration_since(last_press)
                .is_some_and(|elapsed| elapsed <= DIRECTION_DOUBLE_TAP_WINDOW)
        }) {
            self.last_press = None;
            preferred.alternate()
        } else {
            self.last_press = Some(now);
            preferred
        }
    }

    pub fn reset(&mut self) {
        self.last_press = None;
    }
}

pub fn terrain_readout(
    map: Option<&Map>,
    cursor: Option<Cursor>,
    dynamic_terrain_descriptions: bool,
) -> String {
    let Some(map) = map else {
        return "No map available.".into();
    };
    let cursor = cursor.unwrap_or_else(|| Cursor::centered(map));
    let Some(cell) = map.cell(cursor.row, cursor.column) else {
        return "No map available.".into();
    };
    road_topology(map, cursor).map_or_else(
        || cell.spoken_name(dynamic_terrain_descriptions).to_owned(),
        |mut phrase| {
            phrase.push('.');
            phrase
        },
    )
}

pub fn direction_readout(map: Option<&Map>, cursor: Option<Cursor>, style: DirectionStyle) -> String {
    let Some(map) = map else {
        return "No map available.".into();
    };
    let cursor = cursor.unwrap_or_else(|| Cursor::centered(map));
    relative_directions(map, cursor, style).unwrap_or_else(|| "At player position.".into())
}

pub fn dimensions_readout(map: Option<&Map>) -> String {
    map.map_or_else(
        || "No map available.".into(),
        |map| format_dimensions(map.size, map.size),
    )
}

pub fn movement_route(map: Option<&Map>, cursor: Option<Cursor>) -> Result<Vec<String>, MovementRouteError> {
    let map = map.ok_or(MovementRouteError::NoMap)?;
    let route = automatic_route(map, cursor.unwrap_or_else(|| Cursor::centered(map)));
    if route.is_empty() {
        Err(MovementRouteError::PlayerPosition)
    } else {
        Ok(route)
    }
}

pub fn format_dimensions(columns: usize, rows: usize) -> String {
    format!("{columns} by {rows}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Cell, CellKind, CharacterStyle, DynamicTerrainDescription, Rgb, Terrain};

    fn map_with(kind: CellKind) -> Map {
        let style = CharacterStyle {
            foreground: Rgb {
                r: 255,
                g: 255,
                b: 255,
            },
            background: Rgb { r: 0, g: 0, b: 0 },
        };
        Map {
            size: 1,
            cells: vec![Cell {
                token: "T*".into(),
                kind,
                dynamic_terrain_description: None,
                styles: [style; 2],
            }],
            captured_at: 0,
            sequence: 1,
        }
    }

    #[test]
    fn classifies_navigation_and_manual_commands() {
        let plain = KeyModifiers::default();
        assert_eq!(
            classify_key(KEY_UP, plain),
            HostKeyAction::Navigate(Action::North)
        );
        assert_eq!(
            classify_key(KEY_RIGHT, plain),
            HostKeyAction::Navigate(Action::East)
        );
        assert_eq!(
            classify_key(KEY_DOWN, plain),
            HostKeyAction::Navigate(Action::South)
        );
        assert_eq!(
            classify_key(KEY_LEFT, plain),
            HostKeyAction::Navigate(Action::West)
        );
        assert_eq!(
            classify_key(KEY_SPACE, plain),
            HostKeyAction::Navigate(Action::Center)
        );
        assert_eq!(classify_key(KEY_ENTER, plain), HostKeyAction::TerrainReadout);
        assert_eq!(
            classify_key(KEY_NUMPAD_ENTER, plain),
            HostKeyAction::TerrainReadout
        );
        assert_eq!(classify_key(KEY_D, plain), HostKeyAction::DimensionsReadout);
        assert_eq!(classify_key(KEY_H, plain), HostKeyAction::DirectionReadout);
        assert_eq!(classify_key(KEY_T, plain), HostKeyAction::TerrainMenu);
        assert_eq!(classify_key(KEY_M, plain), HostKeyAction::MoveRequest);
        assert_eq!(classify_key(KEY_ESCAPE, plain), HostKeyAction::CancelMove);
        assert_eq!(
            classify_key(
                KEY_SPACE,
                KeyModifiers {
                    control: true,
                    ..KeyModifiers::default()
                }
            ),
            HostKeyAction::FocusMudlet
        );
    }

    #[test]
    fn maps_numlock_numpad_to_eight_way_navigation_and_readouts() {
        let plain = KeyModifiers::default();
        for (key, expected) in [
            (KEY_NUMPAD8, HostKeyAction::Navigate(Action::North)),
            (KEY_NUMPAD9, HostKeyAction::Navigate(Action::Northeast)),
            (KEY_NUMPAD6, HostKeyAction::Navigate(Action::East)),
            (KEY_NUMPAD3, HostKeyAction::Navigate(Action::Southeast)),
            (KEY_NUMPAD2, HostKeyAction::Navigate(Action::South)),
            (KEY_NUMPAD1, HostKeyAction::Navigate(Action::Southwest)),
            (KEY_NUMPAD4, HostKeyAction::Navigate(Action::West)),
            (KEY_NUMPAD7, HostKeyAction::Navigate(Action::Northwest)),
            (KEY_NUMPAD5, HostKeyAction::Navigate(Action::Center)),
            (KEY_NUMPAD0, HostKeyAction::DimensionsReadout),
        ] {
            assert_eq!(classify_key(key, plain), expected);
        }
        assert_eq!(classify_key('8' as i32, plain), HostKeyAction::Consume);
        assert_eq!(classify_key('0' as i32, plain), HostKeyAction::Consume);
    }

    #[test]
    fn classifies_unmodified_virtual_menu_controls() {
        let plain = KeyModifiers::default();
        for (key, expected) in [
            (KEY_UP, MenuCommand::Up),
            (KEY_NUMPAD8, MenuCommand::Up),
            (KEY_DOWN, MenuCommand::Down),
            (KEY_NUMPAD2, MenuCommand::Down),
            (KEY_HOME, MenuCommand::Home),
            (KEY_END, MenuCommand::End),
            (KEY_PAGE_UP, MenuCommand::PageUp),
            (KEY_PAGE_DOWN, MenuCommand::PageDown),
            (KEY_LEFT, MenuCommand::PreviousValue),
            (KEY_NUMPAD4, MenuCommand::PreviousValue),
            (KEY_RIGHT, MenuCommand::NextValue),
            (KEY_NUMPAD6, MenuCommand::NextValue),
            (KEY_ENTER, MenuCommand::Confirm),
            (KEY_NUMPAD_ENTER, MenuCommand::Confirm),
            (KEY_ESCAPE, MenuCommand::Dismiss),
        ] {
            assert_eq!(classify_menu_key(key, plain), Some(expected));
        }
        assert_eq!(classify_menu_key(KEY_T, plain), None);
        assert_eq!(
            classify_menu_key(
                KEY_UP,
                KeyModifiers {
                    shift: true,
                    ..KeyModifiers::default()
                }
            ),
            None
        );
    }

    #[test]
    fn consumes_selection_editing_and_modified_navigation_keys() {
        for key in [8, 9, 127, 323, 341, 65] {
            assert_eq!(classify_key(key, KeyModifiers::default()), HostKeyAction::Consume);
        }
        for modifiers in [
            KeyModifiers {
                shift: true,
                ..KeyModifiers::default()
            },
            KeyModifiers {
                control: true,
                ..KeyModifiers::default()
            },
            KeyModifiers {
                meta: true,
                ..KeyModifiers::default()
            },
        ] {
            assert_eq!(classify_key(KEY_UP, modifiers), HostKeyAction::Consume);
        }
        assert_eq!(
            classify_key(
                9,
                KeyModifiers {
                    shift: true,
                    ..KeyModifiers::default()
                }
            ),
            HostKeyAction::Consume
        );
        assert_eq!(
            classify_key(
                65,
                KeyModifiers {
                    control: true,
                    ..KeyModifiers::default()
                }
            ),
            HostKeyAction::Consume
        );
        assert_eq!(
            classify_key(
                KEY_SPACE,
                KeyModifiers {
                    shift: true,
                    ..KeyModifiers::default()
                }
            ),
            HostKeyAction::Consume
        );
    }

    #[test]
    fn preserves_application_menu_and_system_shortcuts() {
        let control = KeyModifiers {
            control: true,
            ..KeyModifiers::default()
        };
        assert_eq!(classify_key(KEY_COMMA, control), HostKeyAction::PassThrough);
        assert_eq!(
            classify_key(KEY_F10, KeyModifiers::default()),
            HostKeyAction::PassThrough
        );
        for key in [65, KEY_F10, 343] {
            assert_eq!(
                classify_key(
                    key,
                    KeyModifiers {
                        alt: true,
                        ..KeyModifiers::default()
                    }
                ),
                HostKeyAction::PassThrough
            );
        }
    }

    #[test]
    fn terrain_readout_uses_the_cell_announcement_without_displacement() {
        assert_eq!(
            terrain_readout(
                Some(&map_with(CellKind::Player(Some(Terrain::DenseForests)))),
                None,
                false,
            ),
            "Dense forest"
        );
        assert_eq!(
            terrain_readout(Some(&map_with(CellKind::Player(None))), None, false),
            "Player position"
        );
        assert_eq!(
            terrain_readout(Some(&map_with(CellKind::Landmark)), None, false),
            "Landmark"
        );
        assert_eq!(
            terrain_readout(Some(&map_with(CellKind::Unseen)), None, false),
            "Unseen"
        );
        assert_eq!(terrain_readout(None, None, false), "No map available.");
    }

    #[test]
    fn terrain_readout_includes_topology_but_not_displacement() {
        let mut map = map_with(CellKind::Unseen);
        let style = map.cells[0].styles[0];
        map.size = 5;
        map.cells = vec![
            Cell {
                token: "  ".into(),
                kind: CellKind::Unseen,
                dynamic_terrain_description: None,
                styles: [style; 2],
            };
            25
        ];
        let cursor = Cursor { row: 0, column: 2 };
        map.cells[2].kind = CellKind::Terrain(Terrain::Road);
        map.cells[1].kind = CellKind::Terrain(Terrain::Road);
        map.cells[3].kind = CellKind::Terrain(Terrain::Road);

        assert_eq!(
            terrain_readout(Some(&map), Some(cursor), false),
            "Road, east-west."
        );
    }

    #[test]
    fn terrain_readout_selects_dynamic_or_base_name() {
        let mut map = map_with(CellKind::Terrain(Terrain::DenseForests));
        map.cells[0].dynamic_terrain_description = Some(DynamicTerrainDescription::ForestedLakeside);
        assert_eq!(terrain_readout(Some(&map), None, true), "Forested lakeside");
        assert_eq!(terrain_readout(Some(&map), None, false), "Dense forest");
    }

    #[test]
    fn dimensions_put_columns_before_rows() {
        assert_eq!(format_dimensions(7, 5), "7 by 5");
        assert_eq!(dimensions_readout(Some(&map_with(CellKind::Unseen))), "1 by 1");
        assert_eq!(dimensions_readout(None), "No map available.");
    }

    #[test]
    fn direction_readout_handles_map_state_and_selected_style() {
        let mut map = map_with(CellKind::Unseen);
        map.size = 7;
        let cursor = Cursor { row: 1, column: 6 };
        assert_eq!(
            direction_readout(Some(&map), Some(cursor), DirectionStyle::Cardinal),
            "3 east, 2 north"
        );
        assert_eq!(
            direction_readout(Some(&map), Some(cursor), DirectionStyle::Diagonal),
            "2 northeast, 1 east"
        );
        assert_eq!(
            direction_readout(Some(&map), None, DirectionStyle::Diagonal),
            "At player position."
        );
        assert_eq!(
            direction_readout(None, None, DirectionStyle::Diagonal),
            "No map available."
        );
    }

    #[test]
    fn movement_route_requires_a_map_and_non_player_selection() {
        let map = map_with(CellKind::Unseen);
        assert_eq!(movement_route(None, None), Err(MovementRouteError::NoMap));
        assert_eq!(
            movement_route(Some(&map), None),
            Err(MovementRouteError::PlayerPosition)
        );
    }

    #[test]
    fn direction_double_tap_uses_alternate_style_and_resets_after_a_pair() {
        let start = Instant::now();
        let mut tracker = DirectionTapTracker::default();
        assert_eq!(
            tracker.style_for_press(start, DirectionStyle::Cardinal),
            DirectionStyle::Cardinal
        );
        assert_eq!(
            tracker.style_for_press(start + Duration::from_millis(499), DirectionStyle::Cardinal),
            DirectionStyle::Diagonal
        );
        assert_eq!(
            tracker.style_for_press(start + Duration::from_millis(600), DirectionStyle::Cardinal),
            DirectionStyle::Cardinal
        );
    }

    #[test]
    fn direction_double_tap_includes_boundary_and_expires_or_resets() {
        let start = Instant::now();
        let mut tracker = DirectionTapTracker::default();
        assert_eq!(
            tracker.style_for_press(start, DirectionStyle::Diagonal),
            DirectionStyle::Diagonal
        );
        assert_eq!(
            tracker.style_for_press(start + DIRECTION_DOUBLE_TAP_WINDOW, DirectionStyle::Diagonal),
            DirectionStyle::Cardinal
        );

        assert_eq!(
            tracker.style_for_press(start + Duration::from_secs(1), DirectionStyle::Diagonal),
            DirectionStyle::Diagonal
        );
        assert_eq!(
            tracker.style_for_press(start + Duration::from_millis(1501), DirectionStyle::Diagonal,),
            DirectionStyle::Diagonal
        );
        tracker.reset();
        assert_eq!(
            tracker.style_for_press(start + Duration::from_millis(1600), DirectionStyle::Diagonal,),
            DirectionStyle::Diagonal
        );
    }
}
