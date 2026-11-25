#!/usr/bin/env bash
# Request Lasna lREACT by sending Ethereum Sepolia ETH to the official faucet.
# Rate: 1 ETH -> 100 lREACT. Never mainnet. Never prints the deployer key.
set -euo pipefail
export PATH="${HOME}/.foundry/bin:${PATH}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEPOLIA_CHAIN=11155111
LASNA_CHAIN=5318007
SEPOLIA_RPC="${SEPOLIA_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
FAUCET="0x9b9BB25f1A81078C544C829c5EB7822d747Cf434"
VALUE="${1:-0.02ether}"

if [[ -z "${PRIVATE_KEY:-}" ]]; then
  PRIVATE_KEY="$(tr -d '[:space:]' < "$ROOT/deployer.key")"
fi
PRIVATE_KEY="${PRIVATE_KEY#0x}"
ADDR="$(cast wallet address --private-key "$PRIVATE_KEY")"

sid="$(cast chain-id --rpc-url "$SEPOLIA_RPC")"
if [[ "$sid" != "$SEPOLIA_CHAIN" ]]; then
  echo "Refusing: Sepolia RPC chain id $sid"
  exit 1
fi

echo "Deployer: $ADDR"
echo "Sending $VALUE Sepolia ETH to Lasna faucet $FAUCET request($ADDR)"
echo -n "Sepolia ETH before: "; cast balance "$ADDR" --rpc-url "$SEPOLIA_RPC" --ether
echo -n "Lasna lREACT before: "; cast balance "$ADDR" --rpc-url "$LASNA_RPC" --ether

OUT="$(cast send "$FAUCET" --rpc-url "$SEPOLIA_RPC" --private-key "$PRIVATE_KEY" \
  "request(address)" "$ADDR" --value "$VALUE")"
echo "$OUT"
echo
echo "Waiting for lREACT credit on Lasna..."
for i in $(seq 1 40); do
  bal="$(cast balance "$ADDR" --rpc-url "$LASNA_RPC" --ether)"
  echo "  poll $i: $bal lREACT"
  python3 -c "import sys; sys.exit(0 if float('$bal')>0 else 1)" && break
  sleep 15
done
echo -n "Sepolia ETH after: "; cast balance "$ADDR" --rpc-url "$SEPOLIA_RPC" --ether
echo -n "Lasna lREACT after: "; cast balance "$ADDR" --rpc-url "$LASNA_RPC" --ether
