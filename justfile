default: validate lint build test

# objc2/AppKit only build on Apple platforms, so the cargo and nix-binary
# lanes can't compile off Darwin. Until the pasteboard backend is abstracted
# behind a cross-platform trait (amarbel-llc/tacky#3), these recipes no-op
# with a notice on non-macOS hosts so `just` still succeeds for fmt/devShell
# work. Mirrors the flake's isDarwin output gating. Expands to a no-op `true`
# on macOS, or an `echo`+`exit 0` on other platforms. `validate-devshell` and
# `lint-fmt` stay ungated --- they only need Nix eval and run everywhere.
darwin_only := if os() == "macos" { "true" } else { "echo 'skip: macOS-only recipe (objc2 builds only on Apple platforms) --- see amarbel-llc/tacky#3' >&2; exit 0" }

# ---- pre-build --------------------------------------------------------------

validate: validate-devshell

# Verify the devShell evaluates and builds without errors. Catches
# rust-overlay / nixpkgs follows regressions that the prod-binary build
# can mask. No store-output usage --- just a build-check.
[group("pre-build")]
validate-devshell:
    #!/usr/bin/env bash
    set -euo pipefail
    system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
    nix build --no-link --print-build-logs ".#devShells.${system}.default"

lint: lint-fmt lint-clippy

# Read-only formatting gate: builds the `checks.formatting` derivation,
# which runs conformist against a /nix/store snapshot of the source tree
# and fails if anything would change. Does NOT modify files in the
# worktree --- the modifying counterpart is `codemod-fmt-tree`.
[group("pre-build")]
lint-fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
    nix build --no-link --print-build-logs ".#checks.${system}.formatting"

[group("pre-build")]
lint-clippy:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ darwin_only }}
    cargo clippy -- -D warnings

# ---- build ------------------------------------------------------------------

build: build-cargo build-nix

[group("build")]
build-cargo:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ darwin_only }}
    cargo build

# Sandboxed release build via the flake's packages.default. Used by CI.
[group("build")]
build-nix:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ darwin_only }}
    nix build --print-build-logs --no-link

# ---- post-build -------------------------------------------------------------

test: test-cargo test-bats

[group("post-build")]
test-cargo:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ darwin_only }}
    cargo test

# Authoritative bats lane: runs every .bats file inside the nix sandbox
# against a freshly-built `tacky` binary. Tests use isolated, uniquely
# named NSPasteboards (via the --pasteboard flag) so they never touch
# the user's real clipboard.
[group("post-build")]
test-bats:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ darwin_only }}
    system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
    nix build --no-link --print-build-logs ".#packages.${system}.bats-default"

# Run only the bats files carrying `# bats file_tags=<tag>`. Tags are
# auto-discovered at flake-eval time — see bats.nix.
[group("post-build")]
test-bats-tags tag:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ darwin_only }}
    system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
    nix build --no-link --print-build-logs ".#packages.${system}.bats-{{ tag }}"

# Run bats against the host-built `tacky` binary, OUTSIDE the nix
# sandbox. Necessary for pasteboard-tagged tests because the macOS
# nix sandbox can't reach the per-user pboard server. Builds the
# binary via `nix build` (sandboxed), reads the store-path output,
# and runs bats against it under the host's bats from the devShell.
# Pass file globs as args to run a subset, e.g.
# `just test-bats-local pasteboard.bats`.
[group("post-build")]
test-bats-local *targets="*.bats":
    #!/usr/bin/env bash
    set -euo pipefail
    {{ darwin_only }}
    bin=$(nix build --no-link --print-out-paths .#tacky)/bin/tacky
    TACKY_BIN="$bin" \
        BATS_TEST_TIMEOUT=10 \
        bats zz-tests_bats/{{ targets }}

# ---- codemod ----------------------------------------------------------------

codemod-fmt: codemod-fmt-tree

[group("codemod")]
codemod-fmt-tree:
    nix fmt

# ---- maintenance ------------------------------------------------------------

clean: clean-cargo clean-nix

[group("maintenance")]
clean-cargo:
    cargo clean

[group("maintenance")]
clean-nix:
    rm -f result

# ---- maint ------------------------------------------------------------------

# Rewrite TACKY_VERSION in version.env. Staging and committing is release's responsibility.
[group("maint")]
bump-version new_version:
    sed -E -i'' "s/^(export TACKY_VERSION)=.*/\1={{ new_version }}/" version.env

# Create a signed annotated tag from the current version.env and push it.
[group("maint")]
tag message:
    #!/usr/bin/env bash
    set -euo pipefail
    . version.env
    tag="v${TACKY_VERSION:?missing TACKY_VERSION in version.env}"
    git tag -s -m "{{ message }}" "$tag"
    gum log --level info "Created tag: $tag"
    git push origin "$tag"
    gum log --level info "Pushed $tag"
    git tag -v "$tag"

# Orchestrate a full release: bump version.env, commit, tag, gh release create.
[group("maint")]
release new_version:
    #!/usr/bin/env bash
    set -euo pipefail
    branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$branch" != "master" ]]; then
        gum log --level error "release only allowed from master (on '$branch')"
        exit 1
    fi
    prev=$(git tag --sort=-v:refname -l "v*" | head -1)
    header="release v{{ new_version }}"
    if [[ -n "$prev" ]]; then
        summary=$(git log --format='- %s' "$prev"..HEAD)
        msg="$header"$'\n\n'"$summary"
    else
        msg="$header"
    fi
    just bump-version "{{ new_version }}"
    git add version.env
    git commit -m "$header"
    tag="v{{ new_version }}"
    msgfile=$(mktemp)
    printf '%s' "$msg" > "$msgfile"
    git tag -s -F "$msgfile" "$tag"
    rm -f "$msgfile"
    gum log --level info "Created tag: $tag"
    git push origin "$tag"
    gum log --level info "Pushed $tag"
    git tag -v "$tag"
    gh release create "$tag" --title "$header" --notes "$msg"

# ---- ungrouped: developer-loop convenience (not part of `default`) ----------

# Pass-through to `cargo run`. Ungrouped because it's an ad-hoc dev tool.
run-cargo *args:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ darwin_only }}
    cargo run -- {{ args }}

# Auto-rebuild on file change. Ungrouped because it's an ad-hoc dev tool.
watch-cargo:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ darwin_only }}
    cargo watch -x build
