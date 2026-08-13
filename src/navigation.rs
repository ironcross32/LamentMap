use crate::model::{CellKind, Map};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Cursor {
    pub row: usize,
    pub column: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    North,
    East,
    South,
    West,
    Center,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MoveResult {
    Moved,
    Centered,
    Boundary,
}

impl Cursor {
    pub fn centered(map: &Map) -> Self {
        let (row, column) = map.center();
        Self { row, column }
    }

    pub fn apply(&mut self, map: &Map, action: Action) -> MoveResult {
        match action {
            Action::Center => {
                *self = Self::centered(map);
                MoveResult::Centered
            }
            Action::North if self.row > 0 => {
                self.row -= 1;
                MoveResult::Moved
            }
            Action::East if self.column + 1 < map.size => {
                self.column += 1;
                MoveResult::Moved
            }
            Action::South if self.row + 1 < map.size => {
                self.row += 1;
                MoveResult::Moved
            }
            Action::West if self.column > 0 => {
                self.column -= 1;
                MoveResult::Moved
            }
            _ => MoveResult::Boundary,
        }
    }
}

pub fn announcement(map: &Map, cursor: Cursor, announce_directions: bool) -> String {
    let cell = map
        .cell(cursor.row, cursor.column)
        .expect("cursor must remain inside map");
    if cell.kind == CellKind::Player {
        return "Player position, center.".to_owned();
    }
    let mut phrase = cell.kind.spoken_name().to_owned();
    if announce_directions {
        let center = map.size / 2;
        let horizontal = cursor.column.abs_diff(center);
        let vertical = cursor.row.abs_diff(center);
        if horizontal > 0 {
            phrase.push_str(&format!(
                ", {horizontal} {}",
                if cursor.column > center { "east" } else { "west" }
            ));
        }
        if vertical > 0 {
            phrase.push_str(&format!(
                ", {vertical} {}",
                if cursor.row < center { "north" } else { "south" }
            ));
        }
    }
    phrase.push('.');
    phrase
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Cell, CharacterStyle, Rgb};

    fn map() -> Map {
        let style = CharacterStyle {
            foreground: Rgb { r: 0, g: 0, b: 0 },
            background: Rgb { r: 0, g: 0, b: 0 },
        };
        let mut cells = vec![
            Cell {
                token: "  ".into(),
                kind: CellKind::Unseen,
                styles: [style; 2],
            };
            25
        ];
        cells[12].kind = CellKind::Player;
        Map {
            size: 5,
            cells,
            captured_at: 0,
            sequence: 0,
        }
    }

    #[test]
    fn moves_without_wrapping_and_space_always_centers() {
        let map = map();
        let mut cursor = Cursor { row: 0, column: 0 };
        assert_eq!(cursor.apply(&map, Action::North), MoveResult::Boundary);
        assert_eq!(cursor, Cursor { row: 0, column: 0 });
        assert_eq!(cursor.apply(&map, Action::West), MoveResult::Boundary);
        assert_eq!(cursor.apply(&map, Action::East), MoveResult::Moved);
        assert_eq!(cursor.apply(&map, Action::Center), MoveResult::Centered);
        assert_eq!(cursor.apply(&map, Action::Center), MoveResult::Centered);
    }

    #[test]
    fn announces_terrain_then_horizontal_then_vertical() {
        let map = map();
        assert_eq!(
            announcement(&map, Cursor { row: 0, column: 4 }, true),
            "Unseen, 2 east, 2 north."
        );
        assert_eq!(
            announcement(&map, Cursor { row: 2, column: 2 }, true),
            "Player position, center."
        );
        assert_eq!(announcement(&map, Cursor { row: 0, column: 4 }, false), "Unseen.");
    }
}
