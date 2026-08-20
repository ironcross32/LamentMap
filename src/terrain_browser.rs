use crate::menu::MenuItem;
use crate::model::{CellKind, Map, Terrain};
use crate::navigation::Cursor;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerrainTarget {
    Terrain(Terrain),
    Unseen,
}

impl TerrainTarget {
    pub const fn spoken_name(self) -> &'static str {
        match self {
            Self::Terrain(terrain) => terrain.spoken_name(),
            Self::Unseen => "Unseen",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TerrainCatalogEntry {
    target: TerrainTarget,
    coordinates: Vec<Cursor>,
}

impl TerrainCatalogEntry {
    pub const fn target(&self) -> TerrainTarget {
        self.target
    }

    pub fn count(&self) -> usize {
        self.coordinates.len()
    }

    pub fn coordinates(&self) -> &[Cursor] {
        &self.coordinates
    }

    pub fn spoken_message(&self) -> String {
        format!("{}, {}", self.target.spoken_name(), self.count())
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct TerrainCatalog {
    entries: Vec<TerrainCatalogEntry>,
}

impl TerrainCatalog {
    pub fn from_map(map: &Map) -> Self {
        let mut entries: Vec<TerrainCatalogEntry> = Vec::new();
        for (index, cell) in map.cells.iter().enumerate() {
            let target = match cell.kind {
                CellKind::Terrain(terrain) | CellKind::Player(Some(terrain)) => {
                    TerrainTarget::Terrain(terrain)
                }
                CellKind::Unseen => TerrainTarget::Unseen,
                CellKind::Landmark | CellKind::Player(None) => continue,
            };
            let coordinate = Cursor {
                row: index / map.size,
                column: index % map.size,
            };
            if let Some(entry) = entries.iter_mut().find(|entry| entry.target == target) {
                entry.coordinates.push(coordinate);
            } else {
                entries.push(TerrainCatalogEntry {
                    target,
                    coordinates: vec![coordinate],
                });
            }
        }
        entries.sort_by_key(|entry| {
            (
                matches!(entry.target, TerrainTarget::Unseen),
                entry.target.spoken_name(),
            )
        });
        Self { entries }
    }

    pub fn entries(&self) -> &[TerrainCatalogEntry] {
        &self.entries
    }

    pub fn menu_items(&self) -> Vec<MenuItem<TerrainTarget>> {
        self.entries
            .iter()
            .map(|entry| {
                MenuItem::new(entry.target, [entry.spoken_message()])
                    .expect("a catalog entry always has one spoken value")
            })
            .collect()
    }

    pub fn closest(&self, target: TerrainTarget, from: Cursor) -> Option<Cursor> {
        self.entries
            .iter()
            .find(|entry| entry.target == target)?
            .coordinates
            .iter()
            .copied()
            .min_by_key(|coordinate| {
                (
                    coordinate
                        .row
                        .abs_diff(from.row)
                        .max(coordinate.column.abs_diff(from.column)),
                    coordinate.row,
                    coordinate.column,
                )
            })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Cell, CharacterStyle, DynamicTerrainDescription, Rgb};

    const STYLE: CharacterStyle = CharacterStyle {
        foreground: Rgb { r: 0, g: 0, b: 0 },
        background: Rgb { r: 0, g: 0, b: 0 },
    };

    fn cell(kind: CellKind) -> Cell {
        Cell {
            token: "  ".into(),
            kind,
            dynamic_terrain_description: None,
            styles: [STYLE; 2],
        }
    }

    fn map(size: usize, kinds: Vec<CellKind>) -> Map {
        Map {
            size,
            cells: kinds.into_iter().map(cell).collect(),
            captured_at: 0,
            sequence: 1,
        }
    }

    #[test]
    fn counts_present_terrain_and_formats_exact_messages() {
        let catalog = TerrainCatalog::from_map(&map(
            2,
            vec![
                CellKind::Terrain(Terrain::Plains),
                CellKind::Terrain(Terrain::Road),
                CellKind::Terrain(Terrain::Plains),
                CellKind::Unseen,
            ],
        ));
        assert_eq!(
            catalog
                .entries()
                .iter()
                .map(TerrainCatalogEntry::spoken_message)
                .collect::<Vec<_>>(),
            ["Plains, 2", "Road, 1", "Unseen, 1"]
        );
    }

    #[test]
    fn includes_inferred_player_terrain_but_excludes_landmarks_and_ambiguous_players() {
        let catalog = TerrainCatalog::from_map(&map(
            2,
            vec![
                CellKind::Player(Some(Terrain::Hills)),
                CellKind::Player(None),
                CellKind::Landmark,
                CellKind::Terrain(Terrain::Hills),
            ],
        ));
        assert_eq!(catalog.entries().len(), 1);
        assert_eq!(catalog.entries()[0].spoken_message(), "Hills, 2");
        assert_eq!(
            catalog.entries()[0].coordinates(),
            [Cursor { row: 0, column: 0 }, Cursor { row: 1, column: 1 }]
        );
    }

    #[test]
    fn sorts_base_names_alphabetically_with_unseen_last_and_omits_absent_types() {
        let mut input = map(
            2,
            vec![
                CellKind::Unseen,
                CellKind::Terrain(Terrain::Road),
                CellKind::Terrain(Terrain::DenseForests),
                CellKind::Terrain(Terrain::Badlands),
            ],
        );
        input.cells[2].dynamic_terrain_description = Some(DynamicTerrainDescription::ForestedLakeside);
        let catalog = TerrainCatalog::from_map(&input);
        assert_eq!(
            catalog
                .entries()
                .iter()
                .map(|entry| entry.target().spoken_name())
                .collect::<Vec<_>>(),
            ["Badlands", "Dense forest", "Road", "Unseen"]
        );
        assert!(
            catalog
                .entries()
                .iter()
                .all(|entry| entry.target() != TerrainTarget::Terrain(Terrain::Plains))
        );
    }

    #[test]
    fn closest_uses_chebyshev_distance_and_accepts_the_current_tile() {
        let catalog = TerrainCatalog::from_map(&map(
            3,
            vec![
                CellKind::Terrain(Terrain::Road),
                CellKind::Unseen,
                CellKind::Unseen,
                CellKind::Unseen,
                CellKind::Terrain(Terrain::Road),
                CellKind::Unseen,
                CellKind::Unseen,
                CellKind::Unseen,
                CellKind::Terrain(Terrain::Road),
            ],
        ));
        assert_eq!(
            catalog.closest(
                TerrainTarget::Terrain(Terrain::Road),
                Cursor { row: 1, column: 2 }
            ),
            Some(Cursor { row: 1, column: 1 })
        );
        assert_eq!(
            catalog.closest(
                TerrainTarget::Terrain(Terrain::Road),
                Cursor { row: 2, column: 2 }
            ),
            Some(Cursor { row: 2, column: 2 })
        );
    }

    #[test]
    fn closest_breaks_distance_ties_in_row_major_order() {
        let catalog = TerrainCatalog::from_map(&map(
            3,
            vec![
                CellKind::Terrain(Terrain::Road),
                CellKind::Unseen,
                CellKind::Terrain(Terrain::Road),
                CellKind::Unseen,
                CellKind::Unseen,
                CellKind::Unseen,
                CellKind::Terrain(Terrain::Road),
                CellKind::Unseen,
                CellKind::Terrain(Terrain::Road),
            ],
        ));
        assert_eq!(
            catalog.closest(
                TerrainTarget::Terrain(Terrain::Road),
                Cursor { row: 1, column: 1 }
            ),
            Some(Cursor { row: 0, column: 0 })
        );
    }
}
