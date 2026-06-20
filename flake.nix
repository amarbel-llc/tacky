{
  description = "a CLI to manage the macOS pasteboard";

  inputs = {
    nixpkgs.url = "github:amarbel-llc/nixpkgs";
    nixpkgs-master.url = "github:NixOS/nixpkgs/d233902339c02a9c334e7e593de68855ad26c4cb";
    utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102";

    # `nix fmt` entry point. Config lives in ./treefmt.nix.
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # bats helper libraries (bats-support, bats-assert, bats-emo,
    # bats-island) bundled as `bats-libs` with a `batsLibPath` passthru,
    # plus the `batsLane` sandboxed-lane builder under `bats.lib.${system}`.
    # batsLane was migrated out of amarbel-llc/nixpkgs's overlay into the
    # bats flake (amarbel-llc/nixpkgs#16) — consume it here, not via pkgs.
    bats = {
      url = "github:amarbel-llc/bats";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-master.follows = "nixpkgs-master";
      inputs.utils.follows = "utils";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-master,
      utils,
      rust-overlay,
      treefmt-nix,
      bats,
      ...
    }:
    (utils.lib.eachDefaultSystem (
      system:
      let
        tackyVersion =
          let
            raw = builtins.readFile ./version.env;
            m = builtins.match ".*export TACKY_VERSION=([^\n]+).*" raw;
          in
          builtins.elemAt m 0;

        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        inherit (pkgs) lib;

        # tacky links macOS-only objc2/AppKit frameworks, so the binary
        # and every bats lane (which builds it) only build on Darwin.
        # On other systems (e.g. a NixOS host) those outputs are omitted
        # so `nix build` / `nix flake check` don't try — and fail — to
        # compile a macOS binary. The devShell, formatter, and formatting
        # check stay available everywhere for editing on any host.
        isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [
            "rust-src"
            "rustfmt"
          ];
        };

        tackyCommit = self.shortRev or self.dirtyShortRev or "dirty";

        tacky = pkgs.rustPlatform.buildRustPackage {
          pname = "tacky";
          version = tackyVersion;
          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;
          env.TACKY_COMMIT = tackyCommit;
        };

        treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

        bats-libs = bats.packages.${system}.bats-libs;

        # Filter zz-tests_bats so bats-lane store paths only change when
        # actual test inputs change — not on unrelated repo edits.
        tests-src = pkgs.lib.cleanSourceWith {
          src = ./zz-tests_bats;
          filter =
            path: type:
            let
              bn = builtins.baseNameOf path;
            in
            type == "directory"
            || pkgs.lib.hasSuffix ".bats" bn
            || bn == "common.bash"
            || bn == "setup_suite.bash";
        };

        batsLib = import ./bats.nix {
          inherit pkgs bats-libs tacky;
          batsLane = bats.lib.${system}.batsLane;
          batsSrc = tests-src;
        };
      in
      {
        packages = lib.optionalAttrs isDarwin (
          {
            default = tacky;
            inherit tacky;
          }
          // batsLib.batsLaneOutputs
        );

        devShells.default = pkgs.mkShell {
          packages = [
            rustToolchain
            pkgs.rust-analyzer
            pkgs.cargo-watch
            pkgs.uv
            pkgs.bats
            pkgs.gum
          ];
          BATS_LIB_PATH = bats-libs.batsLibPath;
        };

        # `nix fmt` — runs treefmt across the worktree using ./treefmt.nix.
        formatter = treefmtEval.config.build.wrapper;

        # `nix flake check` — read-only formatting gate (sandbox-pure)
        # plus the default bats lane.
        checks = {
          formatting = treefmtEval.config.build.check self;
        }
        // lib.optionalAttrs isDarwin {
          bats-default = batsLib.batsLaneOutputs.bats-default;
        };
      }
    ));
}
