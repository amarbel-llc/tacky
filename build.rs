use std::fs;

fn main() {
    println!("cargo:rerun-if-changed=version.env");

    let content = fs::read_to_string("version.env").expect("version.env not found");
    let version = content
        .lines()
        .find_map(|line| line.strip_prefix("export TACKY_VERSION="))
        .expect("TACKY_VERSION not found in version.env")
        .trim();

    println!("cargo:rustc-env=TACKY_VERSION={version}");
}
