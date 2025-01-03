{
  description = "A libc implemented in Zig";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    systems.url = "github:nix-systems/default-linux";
    flake-utils.url = "github:numtide/flake-utils";
    zig = {
      url = "github:ziglang/zig?ref=pull/20511/head";
      flake = false;
    };
    zon2nix = {
      url = "github:MidstallSoftware/zon2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      flake-utils,
      zon2nix,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;

      defaultOverlay =
        pkgs: prev: with pkgs; {
          zig =
            (prev.zig.overrideAttrs (
              finalAttrs: p: {
                version = "0.14.0-git+${inputs.zig.shortRev or "dirty"}";
                src = inputs.zig;

                doInstallCheck = false;

                postBuild = "";
                postInstall = "";

                outputs = [ "out" ];
              }
            )).override
              {
                llvmPackages = llvmPackages_19;
              };

          zon2nix = stdenv.mkDerivation {
            pname = "zon2nix";
            version = "0.1.2";

            src = lib.cleanSource inputs.zon2nix;

            nativeBuildInputs = [
              pkgs.zig
              pkgs.zig.hook
            ];

            zigBuildFlags = [
              "-Dnix=${lib.getExe nix}"
            ];

            zigCheckFlags = [
              "-Dnix=${lib.getExe nix}"
            ];
          };

          nulibc = callPackage ./nix/package.nix { inherit self; };

          libcCrossChooser = name:
            if name == "nulibc" then targetPackages.nulibc or nulibc
            else prev.libcCrossChooser name;

          pkgsNulibc = import "${nixpkgs}" {
            inherit config;
            overlays = [ (self': super': {
              pkgsNulibc = super';
            })] ++ overlays;
            crossSystem = stdenv.hostPlatform // {
              libc = "nulibc";
              useLLVM = true;
              linker = "lld";
              isStatic = true;
            };
            localSystem = stdenv.hostPlatform;
          };
        };
    in
    flake-utils.lib.eachSystem (import systems) (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system}.appendOverlays [
          defaultOverlay
        ];
      in
      {
        packages = {
          default = pkgs.nulibc;
        };

        devShells = {
          default = pkgs.nulibc.overrideAttrs (
            finalAttrs: p: {
              nativeBuildInputs = p.nativeBuildInputs ++ [
                pkgs.zon2nix
              ];
            }
          );
        };

        legacyPackages = pkgs;
      }
    )
    // {
      overlays = {
        default = defaultOverlay;
        nulibc = defaultOverlay;
      };
    };
}
