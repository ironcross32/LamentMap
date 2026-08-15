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
    pub styles: [CharacterStyle; 2],
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
}
