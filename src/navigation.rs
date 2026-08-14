use crate::model::{CellKind, Map, Terrain};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Cursor {
    pub row: usize,
    pub column: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    North,
    Northeast,
    East,
    Southeast,
    South,
    Southwest,
    West,
    Northwest,
    Center,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MoveResult {
    Moved,
    Centered,
    Boundary,
}

const COMPASS_DIRECTIONS: [(isize, isize, &str); 8] = [
    (-1, 0, "north"),
    (-1, 1, "northeast"),
    (0, 1, "east"),
    (1, 1, "southeast"),
    (1, 0, "south"),
    (1, -1, "southwest"),
    (0, -1, "west"),
    (-1, -1, "northwest"),
];

impl Cursor {
    pub fn centered(map: &Map) -> Self {
        let (row, column) = map.center();
        Self { row, column }
    }

    pub fn apply(&mut self, map: &Map, action: Action) -> MoveResult {
        if action == Action::Center {
            *self = Self::centered(map);
            return MoveResult::Centered;
        }
        let (row_offset, column_offset) = action.offset().expect("non-center action has an offset");
        let Some(row) = self
            .row
            .checked_add_signed(row_offset)
            .filter(|&row| row < map.size)
        else {
            return MoveResult::Boundary;
        };
        let Some(column) = self
            .column
            .checked_add_signed(column_offset)
            .filter(|&column| column < map.size)
        else {
            return MoveResult::Boundary;
        };
        self.row = row;
        self.column = column;
        MoveResult::Moved
    }
}

impl Action {
    const fn offset(self) -> Option<(isize, isize)> {
        match self {
            Self::North => Some((-1, 0)),
            Self::Northeast => Some((-1, 1)),
            Self::East => Some((0, 1)),
            Self::Southeast => Some((1, 1)),
            Self::South => Some((1, 0)),
            Self::Southwest => Some((1, -1)),
            Self::West => Some((0, -1)),
            Self::Northwest => Some((-1, -1)),
            Self::Center => None,
        }
    }
}

pub fn announcement(map: &Map, cursor: Cursor, announce_directions: bool) -> String {
    let cell = map
        .cell(cursor.row, cursor.column)
        .expect("cursor must remain inside map");
    if let Some(mut phrase) = road_topology(map, cursor) {
        if announce_directions {
            let center = map.size / 2;
            let horizontal = cursor.column.abs_diff(center);
            let vertical = cursor.row.abs_diff(center);
            if horizontal > 0 {
                let direction = if cursor.column > center { "east" } else { "west" };
                phrase.push_str(&format!(", {horizontal} {direction}"));
            }
            if vertical > 0 {
                let direction = if cursor.row < center { "north" } else { "south" };
                phrase.push_str(&format!(", {vertical} {direction}"));
            }
        }
        phrase.push('.');
        return phrase;
    }
    if let CellKind::Player(terrain) = cell.kind {
        return terrain.map_or_else(
            || "Player position, center.".to_owned(),
            |terrain| format!("{} (player's position).", terrain.spoken_name()),
        );
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

/// Describes visible road connections around a road, player, or landmark cell.
/// Neighboring connections are inspected clockwise from north.
pub fn road_topology(map: &Map, cursor: Cursor) -> Option<String> {
    let cell = map.cell(cursor.row, cursor.column)?;
    let directions = COMPASS_DIRECTIONS
        .iter()
        .filter_map(|&(row_offset, column_offset, name)| {
            let row = cursor.row.checked_add_signed(row_offset)?;
            let column = cursor.column.checked_add_signed(column_offset)?;
            map.cell(row, column)
                .is_some_and(|neighbor| has_road_terrain(neighbor.kind))
                .then_some(name)
        })
        .collect::<Vec<_>>();

    if directions.len() >= 3
        && matches!(
            cell.kind,
            CellKind::Terrain(Terrain::Road) | CellKind::Player(_) | CellKind::Landmark
        )
    {
        return Some(format!("Crossroads, {}", directions.join(", ")));
    }
    if has_road_terrain(cell.kind) {
        return Some(if directions.is_empty() {
            "Road".to_owned()
        } else {
            format!("Road, {}", directions.join("-"))
        });
    }
    None
}

const fn has_road_terrain(kind: CellKind) -> bool {
    matches!(
        kind,
        CellKind::Terrain(Terrain::Road) | CellKind::Player(Some(Terrain::Road))
    )
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
        cells[12].kind = CellKind::Player(Some(crate::model::Terrain::DenseForests));
        Map {
            size: 5,
            cells,
            captured_at: 0,
            sequence: 0,
        }
    }

    fn topology_map(size: usize, cursor: Cursor, kind: CellKind, roads: &[Action]) -> Map {
        let style = CharacterStyle {
            foreground: Rgb { r: 0, g: 0, b: 0 },
            background: Rgb { r: 0, g: 0, b: 0 },
        };
        let mut map = Map {
            size,
            cells: vec![
                Cell {
                    token: "  ".into(),
                    kind: CellKind::Unseen,
                    styles: [style; 2],
                };
                size * size
            ],
            captured_at: 0,
            sequence: 0,
        };
        map.cells[cursor.row * size + cursor.column].kind = kind;
        for direction in roads {
            let (row_offset, column_offset) = direction.offset().unwrap();
            add_road(&mut map, cursor, row_offset, column_offset);
        }
        map
    }

    fn add_road(map: &mut Map, cursor: Cursor, row_offset: isize, column_offset: isize) {
        let row = cursor.row.checked_add_signed(row_offset).unwrap();
        let column = cursor.column.checked_add_signed(column_offset).unwrap();
        map.cells[row * map.size + column].kind = CellKind::Terrain(Terrain::Road);
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
    fn moves_diagonally_without_wrapping() {
        let map = map();
        let mut cursor = Cursor { row: 2, column: 2 };
        for (action, expected) in [
            (Action::Northeast, Cursor { row: 1, column: 3 }),
            (Action::Southeast, Cursor { row: 2, column: 4 }),
            (Action::Southwest, Cursor { row: 3, column: 3 }),
            (Action::Northwest, Cursor { row: 2, column: 2 }),
        ] {
            assert_eq!(cursor.apply(&map, action), MoveResult::Moved);
            assert_eq!(cursor, expected);
        }

        cursor = Cursor { row: 0, column: 0 };
        for action in [Action::Northwest, Action::Northeast, Action::Southwest] {
            assert_eq!(cursor.apply(&map, action), MoveResult::Boundary);
            assert_eq!(cursor, Cursor { row: 0, column: 0 });
        }
        cursor = Cursor { row: 4, column: 4 };
        for action in [Action::Southeast, Action::Northeast, Action::Southwest] {
            assert_eq!(cursor.apply(&map, action), MoveResult::Boundary);
            assert_eq!(cursor, Cursor { row: 4, column: 4 });
        }
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
            "Dense forest (player's position)."
        );
        assert_eq!(announcement(&map, Cursor { row: 0, column: 4 }, false), "Unseen.");
    }

    #[test]
    fn describes_road_endpoints_straights_turns_and_isolated_cells() {
        let cursor = Cursor { row: 2, column: 2 };
        for (roads, expected) in [
            (&[][..], "Road."),
            (&[Action::East][..], "Road, east."),
            (&[Action::East, Action::West][..], "Road, east-west."),
            (&[Action::North, Action::East][..], "Road, north-east."),
        ] {
            let map = topology_map(5, cursor, CellKind::Terrain(Terrain::Road), roads);
            assert_eq!(announcement(&map, cursor, false), expected);
        }
    }

    #[test]
    fn describes_diagonal_straights_turns_and_endpoints() {
        let cursor = Cursor { row: 2, column: 2 };

        let mut map = topology_map(5, cursor, CellKind::Terrain(Terrain::Road), &[]);
        add_road(&mut map, cursor, -1, 1);
        assert_eq!(announcement(&map, cursor, false), "Road, northeast.");

        add_road(&mut map, cursor, 1, 1);
        assert_eq!(announcement(&map, cursor, false), "Road, northeast-southeast.");

        let mut map = topology_map(5, cursor, CellKind::Terrain(Terrain::Road), &[]);
        add_road(&mut map, cursor, -1, 1);
        add_road(&mut map, cursor, 1, -1);
        assert_eq!(announcement(&map, cursor, false), "Road, northeast-southwest.");
    }

    #[test]
    fn classifies_junctions_and_keeps_fixed_cardinal_order() {
        let cursor = Cursor { row: 2, column: 2 };
        let map = topology_map(
            5,
            cursor,
            CellKind::Terrain(Terrain::Road),
            &[Action::East, Action::South, Action::West],
        );
        assert_eq!(
            announcement(&map, cursor, false),
            "Crossroads, east, south, west."
        );

        let map = topology_map(
            5,
            cursor,
            CellKind::Terrain(Terrain::Road),
            &[Action::West, Action::South, Action::East, Action::North],
        );
        assert_eq!(
            announcement(&map, cursor, false),
            "Crossroads, north, east, south, west."
        );
    }

    #[test]
    fn keeps_fixed_clockwise_order_across_all_eight_directions() {
        let cursor = Cursor { row: 2, column: 2 };
        let mut map = topology_map(5, cursor, CellKind::Terrain(Terrain::Road), &[]);
        for (row_offset, column_offset) in [
            (-1, -1),
            (0, -1),
            (1, -1),
            (1, 0),
            (1, 1),
            (0, 1),
            (-1, 1),
            (-1, 0),
        ] {
            add_road(&mut map, cursor, row_offset, column_offset);
        }
        assert_eq!(
            announcement(&map, cursor, false),
            "Crossroads, north, northeast, east, southeast, south, southwest, west, northwest."
        );
    }

    #[test]
    fn ignores_out_of_bounds_neighbors() {
        let cursor = Cursor { row: 0, column: 0 };
        let map = topology_map(
            3,
            cursor,
            CellKind::Terrain(Terrain::Road),
            &[Action::East, Action::South],
        );
        assert_eq!(announcement(&map, cursor, false), "Road, east-south.");
    }

    #[test]
    fn ignores_out_of_bounds_diagonal_neighbors() {
        let cursor = Cursor { row: 0, column: 0 };
        let mut map = topology_map(3, cursor, CellKind::Terrain(Terrain::Road), &[]);
        add_road(&mut map, cursor, 1, 1);
        assert_eq!(announcement(&map, cursor, false), "Road, southeast.");
    }

    #[test]
    fn only_overlays_with_three_connections_become_crossroads() {
        let cursor = Cursor { row: 2, column: 2 };
        let roads = [Action::North, Action::East, Action::South];

        let terrain = topology_map(5, cursor, CellKind::Terrain(Terrain::DenseForests), &roads);
        assert_eq!(announcement(&terrain, cursor, false), "Dense forest.");

        let two_roads = [Action::East, Action::West];
        let player = topology_map(5, cursor, CellKind::Player(None), &two_roads);
        assert_eq!(announcement(&player, cursor, false), "Player position, center.");
        let landmark = topology_map(5, cursor, CellKind::Landmark, &two_roads);
        assert_eq!(announcement(&landmark, cursor, false), "Landmark.");

        let player = topology_map(5, cursor, CellKind::Player(None), &roads);
        assert_eq!(
            announcement(&player, cursor, false),
            "Crossroads, north, east, south."
        );

        let landmark = topology_map(5, cursor, CellKind::Landmark, &roads);
        assert_eq!(
            announcement(&landmark, cursor, false),
            "Crossroads, north, east, south."
        );

        let player_road = topology_map(
            5,
            cursor,
            CellKind::Player(Some(Terrain::Road)),
            &[Action::East, Action::West],
        );
        assert_eq!(announcement(&player_road, cursor, false), "Road, east-west.");
    }

    #[test]
    fn topology_precedes_optional_displacement() {
        let cursor = Cursor { row: 0, column: 3 };
        let map = topology_map(
            7,
            cursor,
            CellKind::Terrain(Terrain::Road),
            &[Action::East, Action::West],
        );
        assert_eq!(announcement(&map, cursor, true), "Road, east-west, 3 north.");
        assert_eq!(announcement(&map, cursor, false), "Road, east-west.");
    }
}
