with rec
  { sources = import ./nix/sources.nix ;
    pkgs = import sources.nixpkgs {};
    rustPackages =
      with sources;
      (pkgs.callPackage rust-nightly {}).rust {inherit (rust-nightly) date; };

    naersk = pkgs.callPackage ./default.nix
      # We need a more recent rustc for building cargo:
      #   error: internal compiler error: src/librustc/ty/subst.rs:491: Type
      #   parameter `T/#1` (T/1) out of range when substituting (root type=Some(T))
      #   substs=[T]
      { cargo = rustPackages; rustc = rustPackages;
      };
  };

with
  { builtinz = builtins // pkgs.callPackage ./builtins.nix {}; };

rec
{ rustfmt = naersk.buildPackage sources.rustfmt {};
  rustfmt_test = pkgs.runCommand "rustfmt-test"
    { buildInputs = [ rustfmt ]; }
    "rustfmt --help && cargo-fmt --help && touch $out";

  ripgrep = naersk.buildPackage sources.ripgrep {};
  # XXX: executables are missing
  #ripgrep_test = pkgs.runCommand "ripgrep-test"
    #{ buildInputs = [ ripgrep ]; }
    #"rg --help && touch $out";

  ripgrep-all = naersk.buildPackage sources.ripgrep-all {};
  ripgrep-all_test = pkgs.runCommand "ripgrep-all-test"
    { buildInputs = [ ripgrep-all ]; }
    "rga --help && touch $out";

  lorri = naersk.buildPackageIncremental sources.lorri
    { override = _oldAttrs:
        { BUILD_REV_COUNT = 1;
          RUN_TIME_CLOSURE = "${sources.lorri}/nix/runtime.nix";
        };
      doCheck = false;
      inherit cargo;
    };
  lorri_test = pkgs.runCommand "lorri-test" { buildInputs = [ lorri ]; }
    "lorri --help && touch $out";

  talent-plan-1 = naersk.buildPackage "${sources.talent-plan}/rust/projects/project-1" {};
  talent-plan-2 = naersk.buildPackage "${sources.talent-plan}/rust/projects/project-2" {};
  talent-plan-3 = naersk.buildPackage
    "${sources.talent-plan}/rust/projects/project-3"
    { doCheck = false; };

  # TODO: support for git deps
  #test_talent-plan-4 = buildPackage "${sources.talent-plan}/rust/projects/project-4" {};
  #test_talent-plan-5 = buildPackage "${sources.talent-plan}/rust/projects/project-5" {};

  # TODO: change this when niv finally supports submodules
  lucetSrc = pkgs.fetchFromGitHub
    { inherit (sources.lucet) owner repo rev;
      fetchSubmodules = true;
      sha256 = "1vwz7gijq4pcs2dvaazmzcdyb8d64y5qss6s4j2wwigsgqmpfdvs";
    } ;
  lucet = naersk.buildPackageIncremental lucetSrc
    { nativeBuildInputs = [ pkgs.cmake pkgs.python3 ] ;
      doCheck = false;
      inherit cargo;
      targets =
        [ "lucetc"
          "lucet-runtime"
          "lucet-runtime-internals"
          "lucet-module-data"
        ];
    };

  # error in readTOML (remarshal):
  #   Error: Cannot parse as TOML (<string>(92, 14): msg)
  #rust = naersk.buildPackage sources.rust {};

  rustlingsInc = naersk.buildPackageIncremental sources.rustlings
    { inherit cargo; doCheck = false; };

  rustlings = naersk.buildPackage sources.rustlings {};

  simple-dep = naersk.buildPackageIncremental
    (pkgs.lib.cleanSource ./test/simple-dep)
    { inherit cargo; };

  workspace = naersk.buildPackageIncremental
    (pkgs.lib.cleanSource ./test/workspace)
    { inherit cargo; };

  # Fails with some remarshal error
  #servo = naersk.buildPackageIncremental
    #sources.servo
    #{ inherit cargo; };

  # TODO: figure out why 'cargo install' rebuilds some deps
  cargo =
    with rec
      { cargoSrc = sources.cargo ;
        cargoCargoToml = builtinz.readTOML "${cargoSrc}/Cargo.toml";

        # XXX: this works around some hack that breaks the build. For more info
        # on the hack, see
        # https://github.com/rust-lang/rust/blob/b43eb4235ac43c822d903ad26ed806f34cc1a14a/Cargo.toml#L63-L65
        cargoCargoToml' = cargoCargoToml //
          { dependencies = pkgs.lib.filterAttrs (k: _:
              k != "rustc-workspace-hack")
              cargoCargoToml.dependencies;
          };

        cargoCargoLock = "${sources.rust}/Cargo.lock";
      };
    naersk.buildPackage cargoSrc
      { cargolockPath = cargoCargoLock;
        cargotomlPath = builtinz.writeTOML cargoCargoToml';

        # Tests fail, although cargo seems to operate normally
        doCheck = false;

        override = oldAttrs:
          { buildInputs = oldAttrs.buildInputs ++
              [ pkgs.pkgconfig
                pkgs.openssl
                pkgs.libgit2
                pkgs.libiconv
                pkgs.curl
                pkgs.git
              ];
            NIX_LDFLAGS="-F${pkgs.darwin.apple_sdk.frameworks.CoreFoundation}/Library/Frameworks -framework CoreFoundation ";
            LIBGIT2_SYS_USE_PKG_CONFIG = 1;
          };
      };
}
