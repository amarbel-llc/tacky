# bats integration test lanes for tacky.
#
# Wraps `batsLane` from amarbel-llc/bats (`bats.lib.${system}.batsLane`)
# with project-specific defaults: `bats-libs` on `BATS_LIB_PATH`, the
# tacky binary exported via the `binaries` map form, and a
# `BATS_TEST_TIMEOUT` mirroring the per-test wall-clock cap.
#
# Auto-discovers `# bats file_tags=foo,bar` directives at flake-eval
# time and produces one `bats-${tag}` derivation per unique tag plus
# `bats-default` (no filter). Adding/removing tags in a `.bats` file
# invalidates the eval cache — the right behavior, but worth knowing.
#
# Only file-level tags are surfaced; per-`@test` tags are not
# auto-discovered. Use `mkBatsLane` directly for ad-hoc filters.
{
  pkgs,
  bats-libs,
  batsLane,
  tacky,
  batsSrc,
  batsTestTimeout ? "10",
}:
let
  inherit (pkgs) lib;

  mkBatsLane =
    {
      filter ? "",
      base ? tacky,
    }:
    batsLane {
      inherit base filter batsSrc;
      binaries = {
        TACKY_BIN = {
          inherit base;
          name = "tacky";
        };
      };
      batsLibPath = [ bats-libs.batsLibPath ];
      extraEnv = {
        BATS_TEST_TIMEOUT = batsTestTimeout;
      };
      # bats-island's setup_test_home shells out to `git config` to seed
      # a per-test git identity, so the sandbox needs git on PATH. Add
      # coreutils for `realpath`/`stat`/etc. used by helpers.
      nativeBuildInputs = [
        pkgs.git
        pkgs.coreutils
      ];
    };

  batsFiles = lib.filter (f: lib.hasSuffix ".bats" f) (builtins.attrNames (builtins.readDir batsSrc));

  # Strip spaces from a tag string so `file_tags=a, b` doesn't produce
  # a derivation named `bats- b`. Tags are identifiers; internal spaces
  # are not valid, so removing all spaces is safe. Modeled after tap's
  # bats.nix (regex-based trim hit ECMAScript-vs-POSIX portability
  # issues across nix versions).
  stripSpaces = s: builtins.replaceStrings [ " " ] [ "" ] s;

  extractFileTags =
    file:
    let
      content = builtins.readFile (batsSrc + "/${file}");
      lines = lib.splitString "\n" content;
      tagLines = lib.filter (l: lib.hasPrefix "# bats file_tags=" l) lines;
    in
    if tagLines == [ ] then
      [ ]
    else
      map stripSpaces (
        lib.splitString "," (lib.removePrefix "# bats file_tags=" (builtins.head tagLines))
      );

  allFileTags = lib.unique (lib.concatMap extractFileTags batsFiles);

  batsLaneOutputs =
    lib.listToAttrs (
      map (
        tag:
        lib.nameValuePair "bats-${tag}" (mkBatsLane {
          filter = tag;
        })
      ) allFileTags
    )
    // {
      # The default lane skips `pasteboard`-tagged tests because the
      # macOS nix sandbox can't reach the per-user pboard server:
      # +[NSPasteboard pasteboardWithName:] returns NULL inside the
      # build sandbox. Pasteboard tests run only via `just
      # test-bats-local` against ./result/bin/tacky (no sandbox).
      bats-default = mkBatsLane { filter = "!pasteboard"; };
    };
in
{
  inherit mkBatsLane batsLaneOutputs;
}
