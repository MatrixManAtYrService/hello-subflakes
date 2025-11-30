{
  description = "hello-py - Python library with FFI bindings to hello-rs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Relative path input to sibling hello-rs flake
    hello-rs.url = "path:../hello-rs";

    # For creating pure test environments
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, hello-rs, pyproject-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        python = pkgs.python312;

        # Build the wheel using maturin
        # Need to include hello-rs source for the build
        helloPyWheel = pkgs.stdenv.mkDerivation {
          pname = "hello-py-wheel";
          version = "0.1.0";
          src = pkgs.runCommand "hello-py-src" {} ''
            mkdir -p $out
            cp -r ${./.}/* $out/
            chmod -R +w $out
            mkdir -p $out/hello-rs
            cp -r ${../hello-rs}/* $out/hello-rs/
            # Update the Cargo.toml path to point to ./hello-rs instead of ../hello-rs
            sed -i 's|path = "../hello-rs"|path = "./hello-rs"|' $out/Cargo.toml
          '';

          cargoDeps = pkgs.rustPlatform.importCargoLock {
            lockFile = ./Cargo.lock;
          };

          nativeBuildInputs = with pkgs; [
            maturin
            rustPlatform.cargoSetupHook
            cargo
            rustc
          ];

          buildPhase = ''
            maturin build --release --offline --compatibility off --out dist
          '';

          installPhase = ''
            mkdir -p $out
            cp dist/*.whl $out/
            # Create a platform-agnostic symlink for easier referencing
            ln -s $out/*.whl $out/hello_py.whl
          '';
        };

        # Create a Python package from the wheel
        helloPyPackage = python.pkgs.buildPythonPackage rec {
          pname = "hello_py";
          version = "0.1.0";
          format = "other";  # Using custom install phase

          # Use the symlinked wheel file
          src = helloPyWheel;

          # Don't run tests during package build
          doCheck = false;

          # Don't try to unpack - it's already a wheel directory
          dontUnpack = true;
          dontBuild = true;

          # Custom install phase to handle the wheel directory structure
          installPhase = ''
            runHook preInstall
            mkdir -p $out/${python.sitePackages}
            ${pkgs.unzip}/bin/unzip -q ${helloPyWheel}/hello_py.whl -d $out/${python.sitePackages}
            runHook postInstall
          '';
        };

        # Pure test environment with hello-py and pytest
        testEnv = python.withPackages (ps: [
          helloPyPackage
          ps.pytest
          ps.pytest-json-report
        ]);

        # Test runner derivation
        pytestCheck = pkgs.runCommand "hello-py-pytest" {
          buildInputs = [ testEnv ];
        } ''
          export HOME=$TMPDIR
          export PYTHONDONTWRITEBYTECODE=1

          # Copy tests to build directory (Nix store is read-only)
          cp -r ${./tests} ./tests
          chmod -R +w ./tests

          # Run pytest with JSON output for detailed results
          ${testEnv}/bin/pytest ./tests -v --tb=short \
            --json-report --json-report-file=test-results.json

          # Create output directory (required for checks)
          mkdir $out

          # Copy JSON results to output
          cp test-results.json $out/

          # Also create a human-readable summary
          echo "Hello-py pytest results:" > $out/summary.txt
          echo "=======================" >> $out/summary.txt
          ${pkgs.jq}/bin/jq -r '.summary |
            "Total: \(.total // 0) tests\n" +
            "Passed: \(.passed // 0)\n" +
            "Failed: \(.failed // 0)\n" +
            "Skipped: \(.skipped // 0)\n" +
            "Duration: \(.duration // 0)s"' test-results.json >> $out/summary.txt

          # List all test names
          echo "" >> $out/summary.txt
          echo "Tests run:" >> $out/summary.txt
          ${pkgs.jq}/bin/jq -r '.tests[] | "  [\(.outcome)] \(.nodeid)"' test-results.json >> $out/summary.txt

          # Mark as successful
          echo "All tests passed" > $out/result
        '';

      in
      {
        packages = {
          default = testEnv;
          wheel = helloPyWheel;
          # Re-export the Rust library from the subflake
          hello-rs = hello-rs.packages.${system}.default;
          # Expose test environment for debugging
          test-env = testEnv;
        };

        checks = {
          # This runs with `nix flake check`
          pytest = pytestCheck;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            testEnv
            uv
            maturin
            cargo
            rustc
            rust-analyzer
            clippy
            rustfmt
          ];
          shellHook = ''
            export REPO_ROOT=$(pwd)
            echo "Development environment ready!"
            echo ""
            echo "hello-py wheel is installed in this environment"
            echo ""
            echo "To run tests:"
            echo "  pytest tests/ -v"
            echo ""
            echo "To rebuild and test:"
            echo "  nix flake check"
          '';
        };
      });
}
