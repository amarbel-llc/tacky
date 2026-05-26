use std::fs;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=version.env");

    let content = fs::read_to_string("version.env").expect("version.env not found");
    let version = content
        .lines()
        .find_map(|line| line.strip_prefix("export TACKY_VERSION="))
        .expect("TACKY_VERSION not found in version.env")
        .trim()
        .to_owned();

    println!("cargo:rustc-env=TACKY_VERSION={version}");

    // TACKY_COMMIT is injected by the Nix build (flake.nix sets it from
    // self.shortRev). Fall back to git at dev-build time.
    if std::env::var("TACKY_COMMIT").is_err() {
        let commit = Command::new("git")
            .args(["rev-parse", "--short", "HEAD"])
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .map(|s| s.trim().to_owned())
            .unwrap_or_else(|| "unknown".to_owned());
        println!("cargo:rustc-env=TACKY_COMMIT={commit}");
    }
}
