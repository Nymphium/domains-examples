{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    opam-repository = { url = "github:ocaml/opam-repository"; flake = false; };

    flake-utils.url = "github:numtide/flake-utils";

    opam-nix = {
      url = "github:tweag/opam-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        opam-repository.follows = "opam-repository";
      };
    };
  };
  outputs = { self, flake-utils, opam-nix, nixpkgs, ... }:
    let package = "domains-examples";
    in flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        on = opam-nix.lib.${system};
        src = ./.;

        devPackagesQuery = {
          ocaml-lsp-server = "*";
          utop = "*";
        };

        query = devPackagesQuery // {
          # fetch ocaml from nixpkgs, not from opam-repository (it can be done without build)
          ocaml-system = "*";
        };

        scope = on.buildOpamProject' {
          inherit pkgs;
          resolveArgs = { with-test = false; };
        } src query;

        overlay = final: prev: {
          ${package} = prev.${package}.overrideAttrs (_: {
            doNixSupport = false;
            with-test = true;
          });
        };

        scope' = scope.overrideScope' overlay;
        main = scope'.${package};
        devPackages = builtins.attrValues
          (pkgs.lib.getAttrs (builtins.attrNames devPackagesQuery) scope');
      in {
        legacyPackages = scope';

        packages.default = main;

        devShells.default =
          let
            ocamlformat = pkgs.callPackage ./nix/ocamlformat.nix { ocamlformat = ./.ocamlformat; };
          in
          pkgs.mkShell {
            inputsFrom = [ main ];
            buildInputs = devPackages ++ [ ocamlformat ];
          };
    });
}
