{
  projectRootFile = "flake.nix";

  programs.rustfmt.enable = true;
  programs.nixfmt.enable = true;
  programs.taplo.enable = true;
  programs.yamlfmt.enable = true;
  programs.mdformat.enable = true;
  programs.just.enable = true;

  settings.global.excludes = [
    "Cargo.lock"
    "flake.lock"
    "LICENSE"
    ".gitignore"
    ".envrc"
  ];
}
