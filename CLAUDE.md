# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

Tacky is a macOS CLI tool for managing the pasteboard (clipboard). It supports
copying files/stdin to the pasteboard with specific UTI (Uniform Type
Identifier) types and pasting from the pasteboard. Built with Python using
PyObjC bindings to macOS AppKit/Foundation frameworks.

## Build & Development

- **Package manager:** uv
- **Build system:** hatchling (configured in `pyproject.toml`)
- **Dev environment:** direnv + Nix flake
  (`github:friedenberg/dev-flake-templates?dir=python`)
- **Task runner:** just

### Commands

``` bash
uv build              # Build the package
uv publish            # Publish to PyPI
just deploy           # Build + publish
just release          # Bump version, commit, deploy, push
```

### Running locally

``` bash
uv run tacky copy -i public.text <file>    # Copy file to pasteboard
echo "text" | uv run tacky copy -i public.text -   # Copy stdin
uv run tacky paste -u public.text          # Paste from pasteboard
uv run tacky paste --list                  # List available UTI types
```

## Architecture

Single-module Python package. All logic lives in `src/tacky/__init__.py`:

- **CLI layer** (`main`, `cli_copy`, `cli_paste`, `cli_list_uti`):
  argparse-based with `copy` and `paste` subcommands
- **Module API** (`copy`, `paste`, `list_uti`, `write_pasteboard`): Can be
  imported and used programmatically
- **UTI resolution** (`uti_from_argument`): Supports both literal UTI strings
  (e.g. `public.text`) and Apple constants (e.g. `kUTTypePDF`,
  `NSPasteboardType*`) by dynamically loading them from the AppKit bundle

The entrypoint is `tacky:main` (defined in `pyproject.toml [project.scripts]`).

## Key Dependencies

- `pyobjc-core` and `pyobjc-framework-cocoa`: Python-to-Objective-C bridge for
  macOS pasteboard access. This is macOS-only.
