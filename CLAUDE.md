# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

Tacky is a macOS CLI tool for managing the pasteboard (clipboard). It supports
copying files/stdin to the pasteboard with specific UTI (Uniform Type
Identifier) types and pasting from the pasteboard. Built with Rust using objc2
crates for macOS AppKit/Foundation bindings.

## Build & Development

- **Language:** Rust (edition 2024)
- **Dev environment:** direnv + Nix flake (rust-overlay for toolchain)
- **Task runner:** just

### Commands

The justfile follows the verb-noun lifecycle taxonomy from
eng-design_patterns-justfile(7): aggregates compose leaf recipes, `default`
chains them into a single build-and-verify pipeline.

```bash
just                       # default: validate lint build test
just validate              # validate-devshell (nix build --no-link devShell)
just lint                  # lint-fmt + lint-clippy
just lint-fmt              # read-only treefmt gate (builds checks.formatting)
just build                 # build-cargo + build-nix
just test                  # test-cargo + test-bats
just test-bats             # sandboxed bats lane (help tests only)
just test-bats-local       # host-side bats run (all tests, real pboard)
just test-bats-tags <tag>  # one tag (e.g. pasteboard, help)
just codemod-fmt           # nix fmt (modifies the worktree)
just run-cargo <args>      # cargo run -- <args>
just watch-cargo           # cargo watch -x build
just clean                 # cargo clean + rm result
```

Formatting is driven by treefmt-nix (config: `treefmt.nix`). `nix fmt` rewrites
the worktree; `lint-fmt` builds the `checks.formatting` derivation and fails
loudly without rewriting — that's the CI / merge-hook gate.

### CLI Usage

```bash
tacky copy -i public.html <file>              # Copy file to pasteboard
echo "text" | tacky copy -i public.utf8-plain-text -  # Copy stdin
tacky paste -u public.utf8-plain-text         # Paste from pasteboard
tacky paste --list                            # List available UTI types
tacky --pasteboard foo copy -i ... <file>     # Use a named (non-system) pasteboard
```

The optional `-p`/`--pasteboard <name>` flag selects a named NSPasteboard
(created lazily by macOS via `pasteboardWithName:`) instead of the system
clipboard. Used by the bats suite to keep tests from clobbering the real
clipboard.

## Architecture

Single-binary Rust project. All logic lives in `src/main.rs`:

- **CLI** (`Cli`, `Commands`): clap-derive with `copy` and `paste` subcommands
  plus a global `--pasteboard` flag.
- **`get_pasteboard`**: returns `generalPasteboard()` (system clipboard) or
  `pasteboardWithName(...)` when `--pasteboard` is set. The safe objc2 binding
  for `pasteboardWithName` panics on NULL; that only happens when the macOS
  pboard server is unreachable (i.e. inside the nix-darwin sandbox) — outside
  the sandbox it always returns a valid pasteboard.
- **`copy`**: reads files or stdin, writes data via `declareTypes_owner` and
  `setData_forType`. The body is wrapped in `unsafe { ... }` because the
  pasteboard mutation methods are FFI-unsafe.
- **`paste`**: reads a specific UTI via `stringForType`; exits 1 with a
  stderr message if the UTI isn't on the pasteboard.
- **`list_uti`**: enumerates UTI types via `pasteboardItems`.

Users pass raw UTI strings (e.g. `public.html`, `com.adobe.pdf`) directly.

## Testing

Bats integration tests live under `zz-tests_bats/` and are wired via
`bats.nix` (using `bats.lib.${system}.batsLane` from amarbel-llc/bats).

Two lanes, by design:

- **`test-bats`** (sandboxed, CI lane): runs everything *except* tests tagged
  `# bats file_tags=pasteboard`. The macOS nix-darwin build sandbox can't
  reach the per-user pboard server (`+[NSPasteboard pasteboardWithName:]`
  returns NULL inside the sandbox), so pasteboard round-trip tests are
  filtered out here.
- **`test-bats-local`** (host-side): builds `tacky` via `nix build`, then runs
  the full suite against the produced binary under the host's bats. The
  binary still runs outside the sandbox, so the real pboard server is
  reachable. This is the only way to exercise pasteboard tests end-to-end.

Each pasteboard test allocates a unique pasteboard name via
`setup_test_pasteboard` (in `zz-tests_bats/common.bash`), so tests can run in
parallel and never touch the user's real clipboard.

**Bats gotcha — stdin and `run`:** do NOT pipe into `run_tacky`
(`echo x | run_tacky ...`). Bash pipelines spawn a subshell on the right-hand
side; bats's `run` sets `$output`/`$status` *in that subshell* and they don't
propagate back. The test then fails with `output: parameter not set`. Use
`run_tacky_with_stdin "<payload>" <args>` instead — it stages stdin via a
temp file and keeps `run` in the parent shell.

## Key Dependencies

- `clap`: CLI argument parsing with derive macros
- `objc2`, `objc2-foundation`, `objc2-app-kit`: Rust bindings to macOS
  Objective-C frameworks for pasteboard access. macOS-only.
