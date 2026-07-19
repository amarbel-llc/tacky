# tacky's conformist overlay, merged with conformist.lib.presets.eng in
# flake.nix (conformist.lib.evalModule). The preset enables the
# eng-convention linters (eng-versioning, flake-outputs/lock, the
# justfile-* roster); here we choose the formatters and the repo-specific
# tweaks. This is tacky's move off treefmt-nix onto conformist — the last
# repo in the fleet still on treefmt-nix (eng#246).
#
# Every tool treefmt.nix configured has a home here: rustfmt, nixfmt, taplo
# (toml), yamlfmt (yaml, e.g. .github/workflows/*.yml), mdformat (md — note
# unlike most fleet members, tacky formats its own README.md/CLAUDE.md with
# mdformat, so *.md is deliberately NOT excluded below), and just (justfile).
# clippy is added separately, in flake.nix's impure lane (conformist#69 —
# impure because it compiles the crate; see conformistImpureEval).
{ ... }:
{
  programs.rustfmt.enable = true;
  programs.nixfmt.enable = true;
  programs.taplo.enable = true;
  programs.yamlfmt.enable = true;
  programs.mdformat.enable = true;
  programs.just.enable = true;

  # eng-versioning(7): Cargo.toml's [package].name is "tacky" at the tree
  # root, so the derived key (TACKY_VERSION) already matches version.env —
  # no explicit `key` override needed.

  # Excludes, ported verbatim from treefmt.nix's settings.global.excludes.
  settings.excludes = [
    "Cargo.lock"
    "flake.lock"
    "LICENSE"
    ".gitignore"
    ".envrc"
  ];
}
