{
  description = "a CLI to manage the macOS pasteboard";

  inputs = {
    nixpkgs.url = "github:amarbel-llc/nixpkgs";
    nixpkgs-master.url = "github:NixOS/nixpkgs/567a49d1913ce81ac6e9582e3553dd90a955875f";
    utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102";

    # conformist: the linter/formatter multiplexer (treefmt-nix's successor).
    # `nix fmt` entry point. Config lives in ./conformist.nix (+
    # conformist.lib.presets.eng in flake.nix's outputs). Replaces the retired
    # treefmt-nix (eng#246 — tacky was the last fleet holdout).
    conformist = {
      url = "https://code.linenisgreat.com/conformist/archive/master.tar.gz";
      inputs.nixpkgs-master.follows = "nixpkgs-master";
      inputs.utils.follows = "utils";
    };

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
      url = "https://code.linenisgreat.com/bats/archive/master.tar.gz";
      inputs.nixpkgs-master.follows = "nixpkgs-master";
      inputs.utils.follows = "utils";
    };
    utils.inputs.systems.follows = "nixpkgs/systems";
    bats.inputs.igloo.inputs.systems.follows = "nixpkgs/systems";
    bats.inputs.conformist.follows = "conformist";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-master,
      utils,
      rust-overlay,
      conformist,
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
            "clippy"
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

        conformistPkg = conformist.packages.${system}.default;

        # Pure lane: the eng preset (sandboxed eng-convention linters) + this
        # repo's formatters/excludes (./conformist.nix). Drives `nix fmt`
        # (build.wrapper), the sandboxed checks.formatting (build.check), and
        # the conformist-pre-commit hook (build.preCommit).
        conformistEval = conformist.lib.evalModule pkgs {
          imports = [
            conformist.lib.presets.eng
            ./conformist.nix
          ];
          package = conformistPkg;
        };

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
        packages = {
          # The store-pinned `conformist --staged --exit-zero-on-fix` hook
          # from the pure-lane config; the sweatfile (if/when tacky adds one)
          # would name it as the per-commit hook.
          conformist-pre-commit = conformistEval.config.build.preCommit;
          # Its merge-repair sibling: `nix build .#conformist-repair`.
          conformist-repair = conformistEval.config.build.repair;
          # The raw conformist binary.
          conformist = conformistPkg;
        }
        // lib.optionalAttrs isDarwin (
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
            conformistPkg
            conformistEval.config.build.preCommit
            conformistEval.config.build.repair
          ];
          BATS_LIB_PATH = bats-libs.batsLibPath;
        };

        # `nix fmt` — runs the generated conformist wrapper (config +
        # every formatter baked as /nix/store paths) across the worktree.
        formatter = conformistEval.config.build.wrapper;

        # `nix flake check` — read-only formatting gate (sandbox-pure)
        # plus the default bats lane.
        checks = {
          formatting = conformistEval.config.build.check self;
        }
        // lib.optionalAttrs isDarwin {
          bats-default = batsLib.batsLaneOutputs.bats-default;
        };
      }
    ));
}
