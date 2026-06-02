# SPDX-FileCopyrightText: 2026 Edgar Gomes de Araujo <talktoedgar@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

{
  description = "bb_policy — learned policies for Beam Bots";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      treefmt-nix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Pinned to match .tool-versions (Erlang 28 / Elixir 1.19), which stays
        # authoritative for CI. Nix gives a reproducible local shell that agrees.
        erlang = pkgs.beam.packages.erlang_28;
        elixir = erlang.elixir_1_19;

        # treefmt config — one formatter per language. See formatters.md.
        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true; # Nix (nixfmt-rfc-style)
          programs.mix-format.enable = true; # Elixir (uses .formatter.exs)
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            elixir
            erlang.erlang
            lefthook
            reuse # licence/SPDX lint (mix check runs `reuse lint`)

            # Rust toolchain for building the Ortex NIF (ort 2.0-rc). Only used
            # when ORTEX=1 pulls ortex into the build; ort's download-binaries
            # feature fetches a prebuilt onnxruntime at build time (needs network).
            #
            # rustup (not bare rustc) is needed for the Nerves cross-build of the
            # Ortex NIF: it provides `rustup target add aarch64-unknown-linux-gnu`,
            # which Nerves' Rustler integration uses via RUSTLER_TARGET. fwup burns
            # the firmware image. See documentation/how-to/end-to-end-on-pi-zero-2.md.
            rustc
            cargo
            rustup
            fwup
          ];

          # Ortex/ort look these up when linking the NIF.
          env = {
            RUSTLER_NIF_VERSION = "2.16";
          };
        };

        # `nix fmt` runs treefmt across the repo.
        formatter = treefmtEval.config.build.wrapper;

        # `nix flake check` verifies everything is formatted.
        checks.formatting = treefmtEval.config.build.check ./.;
      }
    );
}
