#!/usr/bin/env bash
# Gas comparison matrix across compiler settings.
# Tests Gzip.sol vs GzipYul.sol on all testdata fixtures.
# Usage: bash scripts/gas_matrix.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Ensure testdata exists
[[ -d testdata ]] || ./scripts/gen_testdata

# Restore foundry.toml on exit
cleanup() { cp /tmp/foundry_gas_matrix.toml foundry.toml 2>/dev/null; }
trap cleanup EXIT
cp foundry.toml /tmp/foundry_gas_matrix.toml

# Base config (everything except the params we vary)
base_config() {
    cat << 'EOF'
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
ffi = true
ignored_warnings = ["2018"]
EOF
}

echo "=============================================="
echo " Gas Matrix: Gzip.sol vs GzipYul.sol"
echo "=============================================="
echo ""

# Matrix of settings to test
declare -a via_ir_values=("false" "true")
declare -a opt_values=("false" "true")
declare -a runs_values=(1 200 10000)

printf "%-6s %-6s %-6s %-20s %12s %12s %8s\n" \
    "IR" "OPT" "RUNS" "FILE" "REF_GAS" "YUL_GAS" "SAVE%"
echo "------ ------ ------ -------------------- ------------ ------------ --------"

for via_ir in "${via_ir_values[@]}"; do
    for opt in "${opt_values[@]}"; do
        # via_ir=false + opt=false = stack too deep, skip
        if [[ "$via_ir" == "false" && "$opt" == "false" ]]; then
            continue
        fi
        for runs in "${runs_values[@]}"; do
            # Build foundry.toml
            {
                base_config
                echo "via_ir = $via_ir"
                echo "optimizer = $opt"
                echo "optimizer_runs = $runs"
            } > foundry.toml

            # Compile once
            forge build --silent 2>/dev/null || {
                printf "%-6s %-6s %-6s %-20s %12s %12s %8s\n" \
                    "$via_ir" "$opt" "$runs" "BUILD FAILED" "-" "-" "-"
                continue
            }

            # Run gas comparison (single test that dumps all)
            out=$(forge test --match-contract GzipRoundtrip --match-test test_gasComparison -vv 2>&1) || true

            # Parse log lines like: "  binary ref:414428 yul:187918"
            while IFS= read -r line; do
                if [[ "$line" =~ ([a-z_0-9]+)\ ref:([0-9]+)\ yul:([0-9]+) ]]; then
                    name="${BASH_REMATCH[1]}"
                    ref="${BASH_REMATCH[2]}"
                    yul="${BASH_REMATCH[3]}"
                    pct=$(( (ref - yul) * 100 / ref ))
                    printf "%-6s %-6s %-6s %-20s %12s %12s %7s%%\n" \
                        "$via_ir" "$opt" "$runs" "$name" "$ref" "$yul" "$pct"
                fi
            done <<< "$out"
        done
    done
done

# Restore
cp /tmp/foundry_gas_matrix.toml foundry.toml
echo ""
echo "Done."
