use crate::model::{Cell, CellKind, CharacterStyle, Map, Rgb, Terrain, is_landmark_token};
use serde::Deserialize;
use thiserror::Error;

pub const PROTOCOL_VERSION: u32 = 1;
pub const MAX_INPUT_LINE_BYTES: usize = 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StyleRun {
    pub start: usize,
    pub length: usize,
    pub foreground: Rgb,
    pub background: Rgb,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MapMessage {
    pub protocol_version: u32,
    #[serde(rename = "type")]
    pub message_type: String,
    pub captured_at: u64,
    pub sequence: u64,
    pub rows: Vec<String>,
    pub styles: Vec<Vec<StyleRun>>,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ProtocolError {
    #[error("input line exceeds 1 MiB")]
    Oversized,
    #[error("input is not valid UTF-8")]
    Utf8,
    #[error("malformed JSON: {0}")]
    Json(String),
    #[error("unsupported protocol version {0}")]
    UnsupportedVersion(u32),
    #[error("unsupported message type {0:?}")]
    UnsupportedType(String),
    #[error("map dimension must be a positive odd number")]
    InvalidDimension,
    #[error("row {row} has width {actual}; expected {expected} ASCII characters")]
    InvalidWidth {
        row: usize,
        actual: usize,
        expected: usize,
    },
    #[error("row {0} contains non-ASCII text")]
    NonAscii(usize),
    #[error("style row count does not match map row count")]
    StyleRowCount,
    #[error("style run in row {row} starts at {actual}; expected {expected}")]
    StyleGap {
        row: usize,
        actual: usize,
        expected: usize,
    },
    #[error("style run in row {row} has zero length")]
    EmptyStyleRun { row: usize },
    #[error("style runs in row {row} do not end at width {width}")]
    StyleCoverage { row: usize, width: usize },
    #[error("map must contain exactly one player marker")]
    PlayerCount,
    #[error("player marker must be at raw row {expected_row}, character {expected_column}")]
    PlayerPosition {
        expected_row: usize,
        expected_column: usize,
    },
    #[error("unknown cell token {token:?} at row {row}, column {column}")]
    UnknownToken {
        row: usize,
        column: usize,
        token: String,
    },
}

pub fn parse_line(line: &[u8]) -> Result<Map, ProtocolError> {
    if line.len() > MAX_INPUT_LINE_BYTES {
        return Err(ProtocolError::Oversized);
    }
    let text = std::str::from_utf8(line).map_err(|_| ProtocolError::Utf8)?;
    let message: MapMessage = serde_json::from_str(text.trim_end_matches(['\r', '\n']))
        .map_err(|error| ProtocolError::Json(error.to_string()))?;
    validate(message)
}

pub fn validate(message: MapMessage) -> Result<Map, ProtocolError> {
    if message.protocol_version != PROTOCOL_VERSION {
        return Err(ProtocolError::UnsupportedVersion(message.protocol_version));
    }
    if message.message_type != "map" {
        return Err(ProtocolError::UnsupportedType(message.message_type));
    }
    let size = message.rows.len();
    if size == 0 || size.is_multiple_of(2) {
        return Err(ProtocolError::InvalidDimension);
    }
    let width = size.checked_mul(2).ok_or(ProtocolError::InvalidDimension)?;
    if message.styles.len() != size {
        return Err(ProtocolError::StyleRowCount);
    }

    let mut expanded_styles = Vec::with_capacity(size);
    for (row_index, (row, runs)) in message.rows.iter().zip(&message.styles).enumerate() {
        if !row.is_ascii() {
            return Err(ProtocolError::NonAscii(row_index));
        }
        if row.len() != width {
            return Err(ProtocolError::InvalidWidth {
                row: row_index,
                actual: row.len(),
                expected: width,
            });
        }
        let mut cursor = 0usize;
        let mut styles = Vec::with_capacity(width);
        for run in runs {
            if run.start != cursor {
                return Err(ProtocolError::StyleGap {
                    row: row_index,
                    actual: run.start,
                    expected: cursor,
                });
            }
            if run.length == 0 {
                return Err(ProtocolError::EmptyStyleRun { row: row_index });
            }
            cursor = cursor
                .checked_add(run.length)
                .ok_or(ProtocolError::StyleCoverage {
                    row: row_index,
                    width,
                })?;
            if cursor > width {
                return Err(ProtocolError::StyleCoverage {
                    row: row_index,
                    width,
                });
            }
            styles.extend(std::iter::repeat_n(
                CharacterStyle {
                    foreground: run.foreground,
                    background: run.background,
                },
                run.length,
            ));
        }
        if cursor != width {
            return Err(ProtocolError::StyleCoverage {
                row: row_index,
                width,
            });
        }
        expanded_styles.push(styles);
    }

    let stars: Vec<_> = message
        .rows
        .iter()
        .enumerate()
        .flat_map(|(row, text)| {
            text.bytes()
                .enumerate()
                .filter(|(_, byte)| *byte == b'*')
                .map(move |(column, _)| (row, column))
        })
        .collect();
    if stars.len() != 1 {
        return Err(ProtocolError::PlayerCount);
    }
    let expected = (size / 2, size);
    if stars[0] != expected {
        return Err(ProtocolError::PlayerPosition {
            expected_row: expected.0,
            expected_column: expected.1,
        });
    }

    let mut cells = Vec::with_capacity(size * size);
    for (row_index, row) in message.rows.iter().enumerate() {
        for column in 0..size {
            let start = column * 2;
            let token = &row[start..start + 2];
            let kind = if (row_index, column) == (size / 2, size / 2) {
                CellKind::Player(Terrain::from_player_token(token))
            } else if token == "  " {
                CellKind::Unseen
            } else if is_landmark_token(token) {
                CellKind::Landmark
            } else if let Some(terrain) = Terrain::from_token(token) {
                CellKind::Terrain(terrain)
            } else {
                return Err(ProtocolError::UnknownToken {
                    row: row_index,
                    column,
                    token: token.to_owned(),
                });
            };
            cells.push(Cell {
                token: token.to_owned(),
                kind,
                dynamic_terrain_description: None,
                styles: [
                    expanded_styles[row_index][start],
                    expanded_styles[row_index][start + 1],
                ],
            });
        }
    }

    let mut map = Map {
        size,
        cells,
        captured_at: message.captured_at,
        sequence: message.sequence,
    };
    map.assign_dynamic_terrain_descriptions();
    Ok(map)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn message(size: usize) -> MapMessage {
        let mut rows = vec!["\"\"".repeat(size); size];
        rows[size / 2].replace_range(size..size + 1, "*");
        let style = StyleRun {
            start: 0,
            length: size * 2,
            foreground: Rgb {
                r: 255,
                g: 255,
                b: 255,
            },
            background: Rgb { r: 0, g: 0, b: 0 },
        };
        MapMessage {
            protocol_version: 1,
            message_type: "map".into(),
            captured_at: 1,
            sequence: 2,
            rows,
            styles: vec![vec![style]; size],
        }
    }

    #[test]
    fn accepts_valid_map_and_all_tokens() {
        let mut input = message(5);
        let tokens = [
            "^^", "tt", "TT", "nn", "V-", "/\\", "MM", "sf", "ss", "--", "..", ".n", ".v", "~~", "ii", "==",
            "x\"", "xt", "xT", "ft", "FT", "x^", "x-", "x~",
        ];
        for (index, token) in tokens.iter().enumerate() {
            let row = index / 5;
            let col = index % 5;
            input.rows[row].replace_range(col * 2..col * 2 + 2, token);
        }
        input.rows[2].replace_range(5..6, "*");
        let map = validate(input).unwrap();
        assert_eq!(map.cells.len(), 25);
        assert_eq!(map.cell(2, 2).unwrap().kind, CellKind::Player(None));
    }

    #[test]
    fn infers_only_unambiguous_player_terrain() {
        let map = validate(message(3)).unwrap();
        assert_eq!(
            map.cell(1, 1).unwrap().kind,
            CellKind::Player(Some(Terrain::Plains))
        );

        let mut dense_forest = message(3);
        dense_forest.rows[1].replace_range(2..4, "T*");
        let map = validate(dense_forest).unwrap();
        assert_eq!(
            map.cell(1, 1).unwrap().kind,
            CellKind::Player(Some(Terrain::DenseForests))
        );

        let mut ambiguous = message(3);
        ambiguous.rows[1].replace_range(2..4, "s*");
        let map = validate(ambiguous).unwrap();
        assert_eq!(map.cell(1, 1).unwrap().kind, CellKind::Player(None));

        let mut reversed_swamp_or_light_fungus = message(3);
        reversed_swamp_or_light_fungus.rows[1].replace_range(2..4, "f*");
        let map = validate(reversed_swamp_or_light_fungus).unwrap();
        assert_eq!(map.cell(1, 1).unwrap().kind, CellKind::Player(None));
    }

    #[test]
    fn map_construction_assigns_dynamic_descriptions_without_changing_cells() {
        let mut input = message(3);
        input.rows[1].replace_range(4..6, "x~");
        let map = validate(input).unwrap();
        let player = map.cell(1, 1).unwrap();

        assert_eq!(player.token, "\"*");
        assert_eq!(player.kind, CellKind::Player(Some(Terrain::Plains)));
        assert_eq!(
            player.dynamic_terrain_description,
            Some(crate::model::DynamicTerrainDescription::Riverbank)
        );
        assert_eq!(player.spoken_name(true), "Riverbank");
        assert_eq!(player.spoken_name(false), "Plains");
        assert_eq!(
            map.cell(1, 2).unwrap().kind,
            CellKind::Terrain(Terrain::WastedRivers)
        );
    }

    #[test]
    fn accepts_landmark_overlay_from_live_riverbank_map() {
        let mut input = message(13);
        input.rows = vec![
            "                          ".into(),
            "                ----      ".into(),
            "                ----      ".into(),
            "          tt#T~~--        ".into(),
            "      TTTTTT~~~~          ".into(),
            "    TTTT\"\"~~~~TT          ".into(),
            "    TT\"\"\"\"~~T*TT          ".into(),
            "    \"\"\"\"~~~~TTTT          ".into(),
            "  \"\"\"\"\"\"~~                ".into(),
            "  \"\"\"\"~~                  ".into(),
            "    ~~                    ".into(),
            "                          ".into(),
            "                          ".into(),
        ];
        let map = validate(input).unwrap();
        assert_eq!(map.cell(3, 6).unwrap().token, "#T");
        assert_eq!(map.cell(3, 6).unwrap().kind, CellKind::Landmark);
    }

    #[test]
    fn accepts_reversed_swamp_tokens_from_live_nine_by_nine_map() {
        let mut input = message(9);
        input.rows = vec![
            "        \"\"        ".into(),
            "    fsfs\"\"tt\"\"    ".into(),
            "  sf  tt\"\"tttt==  ".into(),
            "  ttttTT\"\"tt\"\"==  ".into(),
            "TTtt----T*\"\"==\"\"\"\"".into(),
            "  tttt--TTfs==\"\"  ".into(),
            "  TTtt        tt  ".into(),
            "                  ".into(),
            "                  ".into(),
        ];
        let map = validate(input).unwrap();
        assert_eq!(map.cell(1, 2).unwrap().token, "fs");
        assert_eq!(map.cell(1, 2).unwrap().kind, CellKind::Terrain(Terrain::Swamps));
        assert_eq!(map.cell(2, 1).unwrap().token, "sf");
        assert_eq!(map.cell(2, 1).unwrap().kind, CellKind::Terrain(Terrain::Swamps));
    }

    #[test]
    fn accepts_documented_landmark_remainders_but_rejects_unknown_ones() {
        for remainder in [
            '^', '"', 't', 'T', 'n', '-', '\\', 'M', 'f', 's', '.', 'v', '~', 'i', '=',
        ] {
            assert!(is_landmark_token(&format!("#{remainder}")));
            assert!(is_landmark_token(&format!("@{remainder}")));
        }
        assert!(is_landmark_token("##"));
        assert!(is_landmark_token("@@"));
        assert!(!is_landmark_token("#?"));
        assert!(!is_landmark_token("T#"));
    }

    #[test]
    fn preserves_unseen_and_character_styles() {
        let mut input = message(3);
        input.rows[0] = "      ".into();
        input.styles[0] = vec![
            StyleRun {
                length: 1,
                ..input.styles[0][0].clone()
            },
            StyleRun {
                start: 1,
                length: 5,
                foreground: Rgb { r: 1, g: 2, b: 3 },
                background: Rgb { r: 4, g: 5, b: 6 },
            },
        ];
        let map = validate(input).unwrap();
        assert_eq!(map.cell(0, 0).unwrap().kind, CellKind::Unseen);
        assert_ne!(
            map.cell(0, 0).unwrap().styles[0],
            map.cell(0, 0).unwrap().styles[1]
        );
    }

    #[test]
    fn rejects_bad_dimensions_width_player_token_and_styles() {
        assert_eq!(validate(message(4)), Err(ProtocolError::InvalidDimension));
        let mut bad = message(3);
        bad.rows[0].push(' ');
        assert!(matches!(validate(bad), Err(ProtocolError::InvalidWidth { .. })));
        let mut bad = message(3);
        bad.rows[1].replace_range(3..4, "\"");
        assert_eq!(validate(bad), Err(ProtocolError::PlayerCount));
        let mut bad = message(3);
        bad.rows[0].replace_range(0..2, "??");
        assert!(matches!(validate(bad), Err(ProtocolError::UnknownToken { .. })));
        let mut bad = message(3);
        bad.styles[0][0].length -= 1;
        assert!(matches!(validate(bad), Err(ProtocolError::StyleCoverage { .. })));
    }

    #[test]
    fn rejects_unknown_json_fields_and_oversized_lines() {
        let json = br#"{"protocol_version":1,"type":"map","captured_at":1,"sequence":1,"rows":[],"styles":[],"extra":true}"#;
        assert!(matches!(parse_line(json), Err(ProtocolError::Json(_))));
        assert_eq!(
            parse_line(&vec![b' '; MAX_INPUT_LINE_BYTES + 1]),
            Err(ProtocolError::Oversized)
        );
    }
}
