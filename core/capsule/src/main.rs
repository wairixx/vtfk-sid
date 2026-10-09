use regex::Regex;

fn main() {
    let camera_id_pattern = Regex::new(r"^cam-[0-9]{3}$")
        .expect("Invalid camera ID pattern");

    let device_ids = [
        "cam-104",
        "cam-318",
        "cam-209",
        "bad-id",
    ];

    let valid_count = device_ids
        .iter()
        .filter(|id| camera_id_pattern.is_match(id))
        .count();

    println!(
        "Valid camera identifiers: {}/{}",
        valid_count,
        device_ids.len()
    );
}
