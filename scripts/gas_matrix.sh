#!/usr/bin/env bash
# Gas comparison matrix using Foundry profiles + CLI overrides.
# Usage: bash scripts/gas_matrix.sh [profile ...]
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -d testdata ]] || ./scripts/gen_testdata

if [ $# -eq 0 ]; then
    PROFILES=(default ir-opt-no-opt ir-opt-opt ssa-no-opt ssa-opt)
else
    PROFILES=("$@")
fi
# Profiles are defined in foundry.toml

printf "%-25s %-20s %12s %12s %8s\n" "PROFILE" "FILE" "REF_GAS" "YUL_GAS" "SAVE%"
echo "------------------------- -------------------- ------------ ------------ --------"

for profile in "${PROFILES[@]}"; do
    FOUNDRY_PROFILE="$profile" forge build --silent 2>/dev/null || {
        printf "%-25s %-20s %12s %12s %8s\n" "$profile" "BUILD FAILED" "-" "-" "-"
        continue
    }
    out=$(FOUNDRY_PROFILE="$profile" forge test --match-contract GzipRoundtrip --match-test test_gasComparison -vv 2>&1) || true
    while IFS= read -r line; do
        if [[ "$line" =~ ([a-z_0-9]+)\ ref:([0-9]+)\ yul:([0-9]+) ]]; then
            name="${BASH_REMATCH[1]}" ref="${BASH_REMATCH[2]}" yul="${BASH_REMATCH[3]}"
            pct=$(( (ref - yul) * 100 / ref ))
            printf "%-25s %-20s %12s %12s %7s%%\n" "$profile" "$name" "$ref" "$yul" "$pct"
        fi
    done <<< "$out"
done
echo "Done."
