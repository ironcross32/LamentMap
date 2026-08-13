use lament_mapper::model::Rgb;
use lament_mapper::protocol::{MapMessage, StyleRun, validate};

fn validate_fixture(contents: &str, expected_size: usize) {
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
}

#[test]
fn parses_real_thirteen_by_thirteen_html_log_map() {
    validate_fixture(include_str!("fixtures/log_map_13.json"), 13);
}

#[test]
fn parses_real_fifteen_by_fifteen_html_log_map() {
    validate_fixture(include_str!("fixtures/log_map_15.json"), 15);
}
