use lament_mapper::model::{CellKind, Map, Rgb, Terrain};
use lament_mapper::navigation::{Cursor, announcement};
use lament_mapper::protocol::{MapMessage, StyleRun, validate};

fn validate_fixture(contents: &str, expected_size: usize) -> Map {
    let rows: Vec<String> = serde_json::from_str(contents).expect("fixture JSON");
    assert_eq!(rows.len(), expected_size);
    let width = expected_size * 2;
    let style = StyleRun {
        start: 0,
        length: width,
        foreground: Rgb {
            r: 192,
            g: 192,
            b: 192,
        },
        background: Rgb { r: 0, g: 0, b: 0 },
    };
    let map = validate(MapMessage {
        protocol_version: 1,
        message_type: "map".into(),
        captured_at: 1,
        sequence: 1,
        rows,
        styles: vec![vec![style]; expected_size],
    })
    .expect("fixture should be a valid captured map");
    assert_eq!(map.size, expected_size);
    assert_eq!(map.center(), (expected_size / 2, expected_size / 2));
    map
}

#[test]
fn parses_real_thirteen_by_thirteen_html_log_map() {
    let _ = validate_fixture(include_str!("fixtures/log_map_13.json"), 13);
}

#[test]
fn parses_real_fifteen_by_fifteen_html_log_map() {
    let _ = validate_fixture(include_str!("fixtures/log_map_15.json"), 15);
}

#[test]
fn parses_real_thirteen_by_thirteen_diagonal_road_map() {
    let map = validate_fixture(include_str!("fixtures/log_map_13_diagonal_road.json"), 13);

    assert_eq!(
        map.cell(6, 6).unwrap().kind,
        CellKind::Player(Some(Terrain::Road))
    );
    assert_eq!(
        announcement(&map, Cursor { row: 6, column: 6 }, false),
        "Road, east-west."
    );
    assert_eq!(
        announcement(&map, Cursor { row: 6, column: 7 }, false),
        "Road, southeast-west."
    );
    assert_eq!(
        announcement(&map, Cursor { row: 7, column: 8 }, false),
        "Road, southeast-northwest."
    );
}

#[test]
fn parses_real_twenty_one_by_twenty_one_crossroads_map() {
    let map = validate_fixture(include_str!("fixtures/log_map_21_crossroads.json"), 21);
    let cursor = Cursor { row: 10, column: 10 };

    assert_eq!(map.cell(10, 10).unwrap().token, "#*");
    assert_eq!(map.cell(10, 10).unwrap().kind, CellKind::Player(None));
    assert_eq!(map.cell(10, 11).unwrap().kind, CellKind::Terrain(Terrain::Road));
    assert_eq!(map.cell(11, 10).unwrap().kind, CellKind::Terrain(Terrain::Road));
    assert_eq!(map.cell(10, 9).unwrap().kind, CellKind::Terrain(Terrain::Road));
    assert_eq!(
        announcement(&map, cursor, false),
        "Crossroads, east, south, west."
    );
}
