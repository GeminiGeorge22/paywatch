#!/usr/bin/env bash
# Deploy PayWatch to Reactive Lasna + Base Sepolia (testnets only).
# Never commits keys. Never deploys to mainnet.
set -euo pipefail
export PATH="${HOME}/.foundry/bin:${PATH}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Refuse mainnet chain IDs
LASNA_CHAIN=5318007
BASE_SEPOLIA_CHAIN=84532
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
BASE_RPC="${BASE_RPC:-https://sepolia.base.org}"
BASE_CALLBACK_PROXY="0x476F44b11F5C942c58f4c8E3d0300E5710743585"
LASNA_FAUCET_ON_BASE="0x2afaFD298b23b62760711756088F75B7409f5967"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'H'
Usage: script/deploy.sh

Environment:
  PRIVATE_KEY   Deployer key (hex, no 0x or with 0x). If unset, a new key is
                written to ./deployer.key (gitignored) and the script exits
                after printing the address so you can fund it.

Funding required before a successful run:
  1. Base Sepolia ETH to the deployer (public faucet, browser).
  2. lREACT on Lasna: send a small amount of Base Sepolia ETH (e.g. 0.05) to
     the Lasna faucet contract 0x2afaFD298b23b62760711756088F75B7409f5967
     with request(deployer). Rate: 1 ETH -> 100 lREACT. Do not send more than 5 ETH.
  3. Then re-run this script.

This script will not send mainnet transactions.
H
  exit 0
fi

KEYFILE="$ROOT/deployer.key"
if [[ -z "${PRIVATE_KEY:-}" ]]; then
  if [[ -f "$KEYFILE" ]]; then
    PRIVATE_KEY="$(tr -d '[:space:]' < "$KEYFILE")"
  else
    # Generate a fresh key, never print the secret.
    cast wallet new --json > "$ROOT/deployer.wallet.json"
    python3 - <<'PY'
import json, pathlib
raw = pathlib.Path("deployer.wallet.json").read_text()
data = json.loads(raw)
# foundry format: list or dict with address / private_key
if isinstance(data, list):
    data = data[0]
pk = data.get("private_key") or data.get("privateKey")
addr = data.get("address")
pathlib.Path("deployer.key").write_text(pk.strip() + "\n")
pathlib.Path("deployer.address").write_text(addr.strip() + "\n")
print("NEW_DEPLOYER_ADDRESS=" + addr)
PY
    chmod 600 "$KEYFILE" "$ROOT/deployer.wallet.json" "$ROOT/deployer.address"
    ADDR="$(tr -d '[:space:]' < "$ROOT/deployer.address")"
    echo
    echo "Created a fresh testnet deployer: $ADDR"
    echo "The key is in ./deployer.key (gitignored). Do not commit it."
    echo
    echo "Fund it, then re-run this script:"
    echo "  1. Get Base Sepolia ETH into $ADDR from a public faucet."
    echo "  2. Get Lasna lREACT by calling the faucet on Base Sepolia:"
    echo "       cast send $LASNA_FAUCET_ON_BASE --rpc-url $BASE_RPC --private-key \$PRIVATE_KEY \"request(address)\" $ADDR --value 0.004ether"
    echo "  3. ./script/deploy.sh"
    exit 2
  fi
fi

# Normalize key
PRIVATE_KEY="${PRIVATE_KEY#0x}"
ADDR="$(cast wallet address --private-key "$PRIVATE_KEY")"
echo "Deployer: $ADDR"

# Safety: refuse if RPC chain id is not a testnet we named
base_id="$(cast chain-id --rpc-url "$BASE_RPC")"
lasna_id="$(cast chain-id --rpc-url "$LASNA_RPC")"
if [[ "$base_id" != "$BASE_SEPOLIA_CHAIN" ]]; then
  echo "Refusing to deploy: Base RPC chain id $base_id is not Base Sepolia ($BASE_SEPOLIA_CHAIN)"
  exit 1
fi
if [[ "$lasna_id" != "$LASNA_CHAIN" ]]; then
  echo "Refusing to deploy: Lasna RPC chain id $lasna_id is not Lasna ($LASNA_CHAIN)"
  exit 1
fi

base_bal="$(cast balance "$ADDR" --rpc-url "$BASE_RPC")"
lasna_bal="$(cast balance "$ADDR" --rpc-url "$LASNA_RPC")"
echo "Base Sepolia ETH wei: $base_bal"
echo "Lasna lREACT wei:     $lasna_bal"
if [[ "$base_bal" == "0" || "$lasna_bal" == "0" ]]; then
  echo "Deployer is not funded on both testnets yet. See ./script/deploy.sh --help"
  exit 2
fi

echo "== 1/5 PayWatchReactive on Lasna =="
REACT_OUT="$(forge create --broadcast --rpc-url "$LASNA_RPC" --private-key "$PRIVATE_KEY" --value 0.004ether \
  src/PayWatchReactive.sol:PayWatchReactive)"
echo "$REACT_OUT"
REACT_ADDR="$(echo "$REACT_OUT" | awk '/Deployed to:/ {print $3}')"
echo "PayWatchReactive=$REACT_ADDR"

echo "== 2/5 ReceiptRegistry on Base Sepolia =="
REG_OUT="$(forge create --broadcast --rpc-url "$BASE_RPC" --private-key "$PRIVATE_KEY" --value 0.01ether \
  src/ReceiptRegistry.sol:ReceiptRegistry --constructor-args "$BASE_CALLBACK_PROXY" "$REACT_ADDR")"
echo "$REG_OUT"
REG_ADDR="$(echo "$REG_OUT" | awk '/Deployed to:/ {print $3}')"
echo "ReceiptRegistry=$REG_ADDR"

echo "== 3/5 setRegistry =="
cast send "$REACT_ADDR" --rpc-url "$LASNA_RPC" --private-key "$PRIVATE_KEY" \
  "setRegistry(address,uint256)" "$REG_ADDR" "$BASE_SEPOLIA_CHAIN"

echo "== 4/5 DemoToken on Base Sepolia =="
TOK_OUT="$(forge create --broadcast --rpc-url "$BASE_RPC" --private-key "$PRIVATE_KEY" \
  src/DemoToken.sol:DemoToken)"
echo "$TOK_OUT"
TOK_ADDR="$(echo "$TOK_OUT" | awk '/Deployed to:/ {print $3}')"
echo "DemoToken=$TOK_ADDR"
cast send "$TOK_ADDR" --rpc-url "$BASE_RPC" --private-key "$PRIVATE_KEY" \
  "mint(address,uint256)" "$ADDR" 1000000000000

echo "== 5/5 addWatch (min 10 pwUSD) =="
# Merchant is the deployer for the demo. Change MERCHANT to watch a different address.
MERCHANT="${MERCHANT:-$ADDR}"
MIN="${MIN_AMOUNT:-10000000}"
cast send "$REACT_ADDR" --rpc-url "$LASNA_RPC" --private-key "$PRIVATE_KEY" \
  "addWatch(uint256,address,address,uint256)" "$BASE_SEPOLIA_CHAIN" "$TOK_ADDR" "$MERCHANT" "$MIN"

mkdir -p "$ROOT/deployments"
cat > "$ROOT/deployments/84532-5318007.json" <<JSON
{
  "brand": "FMF Tools",
  "track": "Set It and Forget It",
  "networks": {
    "originAndDestination": { "name": "Base Sepolia", "chainId": 84532, "callbackProxy": "$BASE_CALLBACK_PROXY" },
    "reactive": { "name": "Reactive Lasna", "chainId": 5318007 }
  },
  "contracts": {
    "PayWatchReactive": "$REACT_ADDR",
    "ReceiptRegistry": "$REG_ADDR",
    "DemoToken": "$TOK_ADDR"
  },
  "merchant": "$MERCHANT",
  "minAmount": "$MIN",
  "deployer": "$ADDR"
}
JSON
echo "Wrote deployments/84532-5318007.json"
echo "Next: ./script/demo-payment.sh  (sends 25 pwUSD and prints what to wait for on the registry)"
