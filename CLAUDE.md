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

``` bash
just build            # cargo build
just run <args>       # cargo run -- <args>
just check            # cargo clippy + cargo fmt --check
just fmt              # cargo fmt
just watch            # cargo watch -x build
```

### CLI Usage

``` bash
tacky copy -i public.html <file>              # Copy file to pasteboard
echo "text" | tacky copy -i public.utf8-plain-text -  # Copy stdin
tacky paste -u public.utf8-plain-text         # Paste from pasteboard
tacky paste --list                            # List available UTI types
```

## Architecture

Single-binary Rust project. All logic lives in `src/main.rs`:

- **CLI** (`Cli`, `Commands`): clap-derive with `copy` and `paste` subcommands
- **`copy`**: reads files or stdin, writes data to `NSPasteboard` under
  specified UTI types via `declareTypes_owner` and `setData_forType`
- **`paste`**: reads a specific UTI from `NSPasteboard` via `stringForType`
- **`list_uti`**: enumerates UTI types on the pasteboard via `pasteboardItems`

Users pass raw UTI strings (e.g. `public.html`, `com.adobe.pdf`) directly.

## Key Dependencies

- `clap`: CLI argument parsing with derive macros
- `objc2`, `objc2-foundation`, `objc2-app-kit`: Rust bindings to macOS
  Objective-C frameworks for pasteboard access. macOS-only.
