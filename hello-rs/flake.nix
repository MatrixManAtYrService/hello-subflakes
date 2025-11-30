{
  description = "hello-rs - A simple Rust greeting library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        hello-rs = pkgs.rustPlatform.buildRustPackage {
          pname = "hello-rs";
          version = "0.1.0";
          src = ./.;
          cargoLock = {
            lockFile = ./Cargo.lock;
          };
        };
      in
      {
        packages = {
          default = hello-rs;
          hello-rs = hello-rs;
        };

        checks = {
          cargo-test = pkgs.stdenv.mkDerivation {
            name = "hello-rs-cargo-test";
            src = ./.;
            nativeBuildInputs = with pkgs; [ cargo rustc ];

            buildPhase = ''
              # Run cargo test and capture output
              cargo test --no-fail-fast 2>&1 | tee test-output.txt
            '';

            installPhase = ''
              mkdir -p $out

              # Extract test names and results from text output
              grep -E "^test .* \.\.\. (ok|FAILED|ignored)" test-output.txt > test-list.txt || true

              # Extract summary line (e.g., "test result: ok. 2 passed; 0 failed; 0 ignored")
              grep "test result:" test-output.txt | tail -1 > summary-line.txt || echo "No summary found" > summary-line.txt

              # Parse the summary to extract counts
              SUMMARY=$(cat summary-line.txt)
              PASSED=$(echo "$SUMMARY" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' || echo "0")
              FAILED=$(echo "$SUMMARY" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' || echo "0")
              IGNORED=$(echo "$SUMMARY" | grep -oE '[0-9]+ ignored' | grep -oE '[0-9]+' || echo "0")
              TOTAL=$((PASSED + FAILED + IGNORED))

              # Extract duration
              DURATION=$(echo "$SUMMARY" | grep -oE '[0-9]+\.[0-9]+s' || echo "N/A")

              # Create formatted summary
              cat > $out/summary.txt <<EOF
Hello-rs cargo test results:
============================
Total: $TOTAL tests
Passed: $PASSED
Failed: $FAILED
Ignored: $IGNORED
Duration: $DURATION

Tests run:
$(awk '{print "  [" $4 "] " $2}' test-list.txt | sed 's/\.\.\.$//')

EOF

              # Copy full output for debugging
              cp test-output.txt $out/full-output.txt

              # Check if tests passed
              if grep -q "test result: FAILED" test-output.txt; then
                echo "Tests failed!"
                exit 1
              fi

              if ! grep -q "test result: ok" test-output.txt; then
                echo "No test results found!"
                exit 1
              fi
            '';

            doCheck = false;  # We handle testing in buildPhase
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            cargo
            rustc
            rust-analyzer
            clippy
            rustfmt
          ];
        };
      });
}
