
build:
  cargo build

run *args:
  cargo run -- {{args}}

check:
  cargo clippy
  cargo fmt --check

fmt:
  cargo fmt

watch:
  cargo watch -x build
