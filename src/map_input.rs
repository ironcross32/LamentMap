use crate::model::Map;
use crate::navigation::{Action, Cursor, road_topology};

pub const KEY_ENTER: i32 = 13;
pub const KEY_SPACE: i32 = 32;
pub const KEY_COMMA: i32 = 44;
pub const KEY_D: i32 = 68;
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
    FocusMudlet,
    PassThrough,
    Consume,
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
        _ => HostKeyAction::Consume,
    }
}

pub fn terrain_readout(map: Option<&Map>, cursor: Option<Cursor>) -> String {
    let Some(map) = map else {
        return "No map available.".into();
    };
    let cursor = cursor.unwrap_or_else(|| Cursor::centered(map));
    let Some(cell) = map.cell(cursor.row, cursor.column) else {
        return "No map available.".into();
    };
    road_topology(map, cursor).map_or_else(
        || cell.kind.spoken_name().to_owned(),
        |mut phrase| {
            phrase.push('.');
            phrase
        },
    )
}

pub fn dimensions_readout(map: Option<&Map>) -> String {
    map.map_or_else(
        || "No map available.".into(),
        |map| format_dimensions(map.size, map.size),
    )
}

pub fn format_dimensions(columns: usize, rows: usize) -> String {
    format!("{columns} by {rows}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Cell, CellKind, CharacterStyle, Rgb, Terrain};

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
    fn consumes_selection_editing_and_modified_navigation_keys() {
        for key in [8, 9, 27, 127, 323, 341, 65] {
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
                None
            ),
            "Dense forest"
        );
        assert_eq!(
            terrain_readout(Some(&map_with(CellKind::Player(None))), None),
            "Player position"
        );
        assert_eq!(
            terrain_readout(Some(&map_with(CellKind::Landmark)), None),
            "Landmark"
        );
        assert_eq!(terrain_readout(Some(&map_with(CellKind::Unseen)), None), "Unseen");
        assert_eq!(terrain_readout(None, None), "No map available.");
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
                styles: [style; 2],
            };
            25
        ];
        let cursor = Cursor { row: 0, column: 2 };
        map.cells[2].kind = CellKind::Terrain(Terrain::Road);
        map.cells[1].kind = CellKind::Terrain(Terrain::Road);
        map.cells[3].kind = CellKind::Terrain(Terrain::Road);

        assert_eq!(terrain_readout(Some(&map), Some(cursor)), "Road, east-west.");
    }

    #[test]
    fn dimensions_put_columns_before_rows() {
        assert_eq!(format_dimensions(7, 5), "7 by 5");
        assert_eq!(dimensions_readout(Some(&map_with(CellKind::Unseen))), "1 by 1");
        assert_eq!(dimensions_readout(None), "No map available.");
    }
}
