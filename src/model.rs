use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Rgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CharacterStyle {
    pub foreground: Rgb,
    pub background: Rgb,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Terrain {
    Ocean,
    Plains,
    LightForests,
    DenseForests,
    Hills,
    Badlands,
    Mountains,
    HighMountains,
    Swamps,
    Marshes,
    Lakes,
    Deserts,
    DuneDeserts,
    ScrubDeserts,
    Rivers,
    IceFields,
    Road,
    Wasteland,
    WastedLightForests,
    WastedDenseForests,
    LightFungus,
    DenseFungus,
    WastedOcean,
    WastedLakes,
    WastedRivers,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DynamicTerrainDescription {
    Riverbank,
    WoodedRiverbank,
    Seashore,
    ForestedLakeside,
    ForestedMountainside,
}

impl DynamicTerrainDescription {
    pub const fn spoken_name(self) -> &'static str {
        match self {
            Self::Riverbank => "Riverbank",
            Self::WoodedRiverbank => "Wooded riverbank",
            Self::Seashore => "Seashore",
            Self::ForestedLakeside => "Forested lakeside",
            Self::ForestedMountainside => "Forested mountainside",
        }
    }
}

impl Terrain {
    pub const ALL: [Self; 25] = [
        Self::Ocean,
        Self::Plains,
        Self::LightForests,
        Self::DenseForests,
        Self::Hills,
        Self::Badlands,
        Self::Mountains,
        Self::HighMountains,
        Self::Swamps,
        Self::Marshes,
        Self::Lakes,
        Self::Deserts,
        Self::DuneDeserts,
        Self::ScrubDeserts,
        Self::Rivers,
        Self::IceFields,
        Self::Road,
        Self::Wasteland,
        Self::WastedLightForests,
        Self::WastedDenseForests,
        Self::LightFungus,
        Self::DenseFungus,
        Self::WastedOcean,
        Self::WastedLakes,
        Self::WastedRivers,
    ];

    pub fn from_token(token: &str) -> Option<Self> {
        Some(match token {
            "^^" => Self::Ocean,
            "\"\"" => Self::Plains,
            "tt" => Self::LightForests,
            "TT" => Self::DenseForests,
            "nn" => Self::Hills,
            "V-" => Self::Badlands,
            "/\\" => Self::Mountains,
            "MM" => Self::HighMountains,
            "sf" | "fs" => Self::Swamps,
            "ss" => Self::Marshes,
            "--" => Self::Lakes,
            ".." => Self::Deserts,
            ".n" => Self::DuneDeserts,
            ".v" => Self::ScrubDeserts,
            "~~" => Self::Rivers,
            "ii" => Self::IceFields,
            "==" => Self::Road,
            "x\"" => Self::Wasteland,
            "xt" => Self::WastedLightForests,
            "xT" => Self::WastedDenseForests,
            "ft" => Self::LightFungus,
            "FT" => Self::DenseFungus,
            "x^" => Self::WastedOcean,
            "x-" => Self::WastedLakes,
            "x~" => Self::WastedRivers,
            _ => return None,
        })
    }

    /// Infers terrain only when the visible first character of a player token
    /// belongs to exactly one documented terrain token.
    pub fn from_player_token(token: &str) -> Option<Self> {
        Some(match token.as_bytes() {
            b"^*" => Self::Ocean,
            b"\"*" => Self::Plains,
            b"t*" => Self::LightForests,
            b"T*" => Self::DenseForests,
            b"n*" => Self::Hills,
            b"V*" => Self::Badlands,
            b"/*" => Self::Mountains,
            b"M*" => Self::HighMountains,
            b"-*" => Self::Lakes,
            b"~*" => Self::Rivers,
            b"i*" => Self::IceFields,
            b"=*" => Self::Road,
            b"F*" => Self::DenseFungus,
            // s*, f*, .*, and x* each match multiple terrain tokens.
            _ => return None,
        })
    }

    pub const fn cue_id(self) -> &'static str {
        match self {
            Self::Ocean => "ocean",
            Self::Plains => "plains",
            Self::LightForests => "light_forests",
            Self::DenseForests => "dense_forests",
            Self::Hills => "hills",
            Self::Badlands => "badlands",
            Self::Mountains => "mountains",
            Self::HighMountains => "high_mountains",
            Self::Swamps => "swamps",
            Self::Marshes => "marshes",
            Self::Lakes => "lakes",
            Self::Deserts => "deserts",
            Self::DuneDeserts => "dune_deserts",
            Self::ScrubDeserts => "scrub_deserts",
            Self::Rivers => "rivers",
            Self::IceFields => "ice_fields",
            Self::Road => "road",
            Self::Wasteland => "wasteland",
            Self::WastedLightForests => "wasted_light_forests",
            Self::WastedDenseForests => "wasted_dense_forests",
            Self::LightFungus => "light_fungus",
            Self::DenseFungus => "dense_fungus",
            Self::WastedOcean => "wasted_ocean",
            Self::WastedLakes => "wasted_lakes",
            Self::WastedRivers => "wasted_rivers",
        }
    }

    pub const fn spoken_name(self) -> &'static str {
        match self {
            Self::Ocean => "Ocean",
            Self::Plains => "Plains",
            Self::LightForests => "Light forest",
            Self::DenseForests => "Dense forest",
            Self::Hills => "Hills",
            Self::Badlands => "Badlands",
            Self::Mountains => "Mountains",
            Self::HighMountains => "High mountains",
            Self::Swamps => "Swamps",
            Self::Marshes => "Marshes",
            Self::Lakes => "Lakes",
            Self::Deserts => "Desert",
            Self::DuneDeserts => "Dune desert",
            Self::ScrubDeserts => "Scrub desert",
            Self::Rivers => "River",
            Self::IceFields => "Ice fields",
            Self::Road => "Road",
            Self::Wasteland => "Wasteland",
            Self::WastedLightForests => "Wasted light forest",
            Self::WastedDenseForests => "Wasted dense forest",
            Self::LightFungus => "Light fungus",
            Self::DenseFungus => "Dense fungus",
            Self::WastedOcean => "Wasted ocean",
            Self::WastedLakes => "Wasted lakes",
            Self::WastedRivers => "Wasted river",
        }
    }
}

/// Returns true for either complete landmark glyph (`##` or `@@`) or a
/// first-character landmark overlay whose second character is the unobscured
/// remainder of a documented terrain token.
pub fn is_landmark_token(token: &str) -> bool {
    let bytes = token.as_bytes();
    if bytes.len() != 2 || !matches!(bytes[0], b'#' | b'@') {
        return false;
    }
    if bytes[0] == bytes[1] {
        return true;
    }
    Terrain::ALL
        .iter()
        .any(|terrain| terrain_token_remainder(*terrain) == bytes[1])
}

const fn terrain_token_remainder(terrain: Terrain) -> u8 {
    match terrain {
        Terrain::Ocean | Terrain::WastedOcean => b'^',
        Terrain::Plains | Terrain::Wasteland => b'"',
        Terrain::LightForests | Terrain::LightFungus | Terrain::WastedLightForests => b't',
        Terrain::DenseForests | Terrain::DenseFungus | Terrain::WastedDenseForests => b'T',
        Terrain::Hills | Terrain::DuneDeserts => b'n',
        Terrain::Badlands | Terrain::Lakes | Terrain::WastedLakes => b'-',
        Terrain::Mountains => b'\\',
        Terrain::HighMountains => b'M',
        Terrain::Swamps => b'f',
        Terrain::Marshes => b's',
        Terrain::Deserts => b'.',
        Terrain::ScrubDeserts => b'v',
        Terrain::Rivers | Terrain::WastedRivers => b'~',
        Terrain::IceFields => b'i',
        Terrain::Road => b'=',
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CellKind {
    Terrain(Terrain),
    Landmark,
    Player(Option<Terrain>),
    Unseen,
}

impl CellKind {
    pub const fn spoken_name(self) -> &'static str {
        match self {
            Self::Terrain(terrain) => terrain.spoken_name(),
            Self::Landmark => "Landmark",
            Self::Player(Some(terrain)) => terrain.spoken_name(),
            Self::Player(None) => "Player position",
            Self::Unseen => "Unseen",
        }
    }

    pub const fn cue_id(self) -> &'static str {
        match self {
            Self::Terrain(terrain) => terrain.cue_id(),
            Self::Landmark => "landmark",
            Self::Player(_) => "player",
            Self::Unseen => "unseen",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Cell {
    pub token: String,
    pub kind: CellKind,
    pub dynamic_terrain_description: Option<DynamicTerrainDescription>,
    pub styles: [CharacterStyle; 2],
}

impl Cell {
    pub const fn spoken_name(&self, dynamic_terrain_descriptions: bool) -> &'static str {
        if dynamic_terrain_descriptions && let Some(description) = self.dynamic_terrain_description {
            description.spoken_name()
        } else {
            self.kind.spoken_name()
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Map {
    pub size: usize,
    pub cells: Vec<Cell>,
    pub captured_at: u64,
    pub sequence: u64,
}

impl Map {
    pub fn center(&self) -> (usize, usize) {
        (self.size / 2, self.size / 2)
    }

    pub fn cell(&self, row: usize, column: usize) -> Option<&Cell> {
        (row < self.size && column < self.size).then(|| &self.cells[row * self.size + column])
    }

    pub fn assign_dynamic_terrain_descriptions(&mut self) {
        for index in 0..self.cells.len() {
            let row = index / self.size;
            let column = index % self.size;
            self.cells[index].dynamic_terrain_description = dynamic_terrain_description(self, row, column);
        }
    }
}

fn dynamic_terrain_description(map: &Map, row: usize, column: usize) -> Option<DynamicTerrainDescription> {
    let terrain = terrain_from_kind(map.cell(row, column)?.kind)?;
    let adjacent_to = |matches_terrain: fn(Terrain) -> bool| {
        (-1..=1).any(|row_offset| {
            (-1..=1).any(|column_offset| {
                if row_offset == 0 && column_offset == 0 {
                    return false;
                }
                let Some(neighbor_row) = row.checked_add_signed(row_offset) else {
                    return false;
                };
                let Some(neighbor_column) = column.checked_add_signed(column_offset) else {
                    return false;
                };
                map.cell(neighbor_row, neighbor_column)
                    .and_then(|neighbor| terrain_from_kind(neighbor.kind))
                    .is_some_and(matches_terrain)
            })
        })
    };

    match terrain {
        Terrain::Plains if adjacent_to(is_river) => Some(DynamicTerrainDescription::Riverbank),
        Terrain::Plains if adjacent_to(is_ocean) => Some(DynamicTerrainDescription::Seashore),
        Terrain::LightForests | Terrain::DenseForests if adjacent_to(is_river) => {
            Some(DynamicTerrainDescription::WoodedRiverbank)
        }
        Terrain::LightForests | Terrain::DenseForests if adjacent_to(is_lake) => {
            Some(DynamicTerrainDescription::ForestedLakeside)
        }
        Terrain::LightForests | Terrain::DenseForests if adjacent_to(is_mountain) => {
            Some(DynamicTerrainDescription::ForestedMountainside)
        }
        _ => None,
    }
}

const fn terrain_from_kind(kind: CellKind) -> Option<Terrain> {
    match kind {
        CellKind::Terrain(terrain) | CellKind::Player(Some(terrain)) => Some(terrain),
        CellKind::Landmark | CellKind::Player(None) | CellKind::Unseen => None,
    }
}

const fn is_river(terrain: Terrain) -> bool {
    matches!(terrain, Terrain::Rivers | Terrain::WastedRivers)
}

const fn is_ocean(terrain: Terrain) -> bool {
    matches!(terrain, Terrain::Ocean | Terrain::WastedOcean)
}

const fn is_lake(terrain: Terrain) -> bool {
    matches!(terrain, Terrain::Lakes | Terrain::WastedLakes)
}

const fn is_mountain(terrain: Terrain) -> bool {
    matches!(terrain, Terrain::Mountains | Terrain::HighMountains)
}

#[cfg(test)]
mod tests {
    use super::*;

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

    fn map_with_neighbors(
        target: CellKind,
        target_position: (usize, usize),
        neighbors: &[((usize, usize), Terrain)],
    ) -> Map {
        let mut map = Map {
            size: 3,
            cells: vec![cell(CellKind::Unseen); 9],
            captured_at: 0,
            sequence: 0,
        };
        map.cells[target_position.0 * map.size + target_position.1].kind = target;
        for &((row, column), terrain) in neighbors {
            map.cells[row * map.size + column].kind = CellKind::Terrain(terrain);
        }
        map.assign_dynamic_terrain_descriptions();
        map
    }

    fn center_description(
        target: CellKind,
        neighbors: &[((usize, usize), Terrain)],
    ) -> Option<DynamicTerrainDescription> {
        map_with_neighbors(target, (1, 1), neighbors)
            .cell(1, 1)
            .unwrap()
            .dynamic_terrain_description
    }

    #[test]
    fn assigns_every_rule_for_cardinal_and_diagonal_neighbors() {
        for (target, trigger, expected) in [
            (
                CellKind::Terrain(Terrain::Plains),
                Terrain::Rivers,
                DynamicTerrainDescription::Riverbank,
            ),
            (
                CellKind::Terrain(Terrain::Plains),
                Terrain::Ocean,
                DynamicTerrainDescription::Seashore,
            ),
            (
                CellKind::Terrain(Terrain::LightForests),
                Terrain::Rivers,
                DynamicTerrainDescription::WoodedRiverbank,
            ),
            (
                CellKind::Terrain(Terrain::DenseForests),
                Terrain::Lakes,
                DynamicTerrainDescription::ForestedLakeside,
            ),
            (
                CellKind::Terrain(Terrain::LightForests),
                Terrain::Mountains,
                DynamicTerrainDescription::ForestedMountainside,
            ),
        ] {
            for position in [(1, 2), (2, 2)] {
                assert_eq!(
                    center_description(target, &[(position, trigger)]),
                    Some(expected),
                    "{target:?} beside {trigger:?} at {position:?}"
                );
            }
        }
    }

    #[test]
    fn checks_only_in_bounds_neighbors_at_map_edges() {
        for (target, trigger, expected) in [
            (
                Terrain::Plains,
                Terrain::Rivers,
                DynamicTerrainDescription::Riverbank,
            ),
            (
                Terrain::Plains,
                Terrain::Ocean,
                DynamicTerrainDescription::Seashore,
            ),
            (
                Terrain::LightForests,
                Terrain::Rivers,
                DynamicTerrainDescription::WoodedRiverbank,
            ),
            (
                Terrain::DenseForests,
                Terrain::Lakes,
                DynamicTerrainDescription::ForestedLakeside,
            ),
            (
                Terrain::LightForests,
                Terrain::Mountains,
                DynamicTerrainDescription::ForestedMountainside,
            ),
        ] {
            for trigger_position in [(0, 1), (1, 1)] {
                let map =
                    map_with_neighbors(CellKind::Terrain(target), (0, 0), &[(trigger_position, trigger)]);
                assert_eq!(
                    map.cell(0, 0).unwrap().dynamic_terrain_description,
                    Some(expected)
                );
            }
        }
    }

    #[test]
    fn accepts_water_variants_mountain_heights_and_both_forest_densities() {
        for (target, trigger, expected) in [
            (
                Terrain::Plains,
                Terrain::WastedRivers,
                DynamicTerrainDescription::Riverbank,
            ),
            (
                Terrain::Plains,
                Terrain::WastedOcean,
                DynamicTerrainDescription::Seashore,
            ),
            (
                Terrain::LightForests,
                Terrain::WastedRivers,
                DynamicTerrainDescription::WoodedRiverbank,
            ),
            (
                Terrain::DenseForests,
                Terrain::Rivers,
                DynamicTerrainDescription::WoodedRiverbank,
            ),
            (
                Terrain::LightForests,
                Terrain::WastedLakes,
                DynamicTerrainDescription::ForestedLakeside,
            ),
            (
                Terrain::DenseForests,
                Terrain::Lakes,
                DynamicTerrainDescription::ForestedLakeside,
            ),
            (
                Terrain::LightForests,
                Terrain::HighMountains,
                DynamicTerrainDescription::ForestedMountainside,
            ),
            (
                Terrain::DenseForests,
                Terrain::Mountains,
                DynamicTerrainDescription::ForestedMountainside,
            ),
        ] {
            assert_eq!(
                center_description(CellKind::Terrain(target), &[((1, 2), trigger)],),
                Some(expected),
                "{target:?} beside {trigger:?}"
            );
        }
    }

    #[test]
    fn assigns_descriptions_to_inferred_player_terrain() {
        for (target, trigger, expected) in [
            (
                Terrain::Plains,
                Terrain::Rivers,
                DynamicTerrainDescription::Riverbank,
            ),
            (
                Terrain::LightForests,
                Terrain::WastedLakes,
                DynamicTerrainDescription::ForestedLakeside,
            ),
            (
                Terrain::DenseForests,
                Terrain::HighMountains,
                DynamicTerrainDescription::ForestedMountainside,
            ),
        ] {
            assert_eq!(
                center_description(CellKind::Player(Some(target)), &[((0, 0), trigger)],),
                Some(expected)
            );
        }
    }

    #[test]
    fn resolves_multiple_matches_in_documented_precedence_order() {
        assert_eq!(
            center_description(
                CellKind::Terrain(Terrain::Plains),
                &[((0, 1), Terrain::Ocean), ((1, 2), Terrain::Rivers)],
            ),
            Some(DynamicTerrainDescription::Riverbank)
        );
        assert_eq!(
            center_description(
                CellKind::Terrain(Terrain::DenseForests),
                &[
                    ((0, 1), Terrain::Mountains),
                    ((1, 2), Terrain::Lakes),
                    ((2, 1), Terrain::Rivers),
                ],
            ),
            Some(DynamicTerrainDescription::WoodedRiverbank)
        );
        assert_eq!(
            center_description(
                CellKind::Terrain(Terrain::DenseForests),
                &[((0, 1), Terrain::HighMountains), ((1, 2), Terrain::WastedLakes)],
            ),
            Some(DynamicTerrainDescription::ForestedLakeside)
        );
    }

    #[test]
    fn excludes_unmatched_terrain_special_forests_landmarks_and_ambiguous_players() {
        for target in [
            CellKind::Terrain(Terrain::Plains),
            CellKind::Terrain(Terrain::Hills),
            CellKind::Terrain(Terrain::WastedLightForests),
            CellKind::Terrain(Terrain::WastedDenseForests),
            CellKind::Terrain(Terrain::LightFungus),
            CellKind::Terrain(Terrain::DenseFungus),
            CellKind::Landmark,
            CellKind::Player(None),
            CellKind::Unseen,
        ] {
            assert_eq!(
                center_description(target, &[((0, 0), Terrain::HighMountains)]),
                None,
                "{target:?}"
            );
        }
        assert_eq!(
            center_description(CellKind::Terrain(Terrain::LightForests), &[]),
            None
        );
    }

    #[test]
    fn cell_name_selects_dynamic_or_unchanged_base_terrain() {
        let cell = Cell {
            token: "\"\"".into(),
            kind: CellKind::Terrain(Terrain::Plains),
            dynamic_terrain_description: Some(DynamicTerrainDescription::Riverbank),
            styles: [STYLE; 2],
        };
        assert_eq!(cell.spoken_name(true), "Riverbank");
        assert_eq!(cell.spoken_name(false), "Plains");
        assert_eq!(cell.kind, CellKind::Terrain(Terrain::Plains));
        assert_eq!(cell.token, "\"\"");
    }
}
