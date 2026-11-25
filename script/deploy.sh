#!/usr/bin/env bash
# Deploy PayWatch to Reactive Lasna + Ethereum Sepolia (testnets only).
# Never commits keys. Never deploys to mainnet.
set -euo pipefail
export PATH="${HOME}/.foundry/bin:${PATH}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LASNA_CHAIN=5318007
SEPOLIA_CHAIN=11155111
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
SEPOLIA_RPC="${SEPOLIA_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
SEPOLIA_CALLBACK_PROXY="0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4"
LASNA_FAUCET_ON_SEPOLIA="0x9b9BB25f1A81078C544C829c5EB7822d747Cf434"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'H'
Usage: script/deploy.sh

Deploys PayWatch to Ethereum Sepolia (origin + destination) and Reactive Lasna.
Refuses any RPC that is not those two testnets. Never sends mainnet transactions.

Environment:
  PRIVATE_KEY   Deployer key. If unset, ./deployer.key (gitignored) is used.

Funding:
  1. Ethereum Sepolia ETH on the deployer.
  2. lREACT: script/request-lreact.sh (0.02 Sepolia ETH -> 2 lREACT by default).
H
  exit 0
fi

KEYFILE="$ROOT/deployer.key"
if [[ -z "${PRIVATE_KEY:-}" ]]; then
  if [[ -f "$KEYFILE" ]]; then
    PRIVATE_KEY="$(tr -d '[:space:]' < "$KEYFILE")"
  else
    echo "missing deployer.key and PRIVATE_KEY; refuse to invent a new key during a funded deploy"
    exit 2
  fi
fi
PRIVATE_KEY="${PRIVATE_KEY#0x}"
ADDR="$(cast wallet address --private-key "$PRIVATE_KEY")"
echo "Deployer: $ADDR"

sepolia_id="$(cast chain-id --rpc-url "$SEPOLIA_RPC")"
lasna_id="$(cast chain-id --rpc-url "$LASNA_RPC")"
if [[ "$sepolia_id" != "$SEPOLIA_CHAIN" ]]; then
  echo "Refusing to deploy: Sepolia RPC chain id $sepolia_id is not Ethereum Sepolia ($SEPOLIA_CHAIN)"
  exit 1
fi
if [[ "$lasna_id" != "$LASNA_CHAIN" ]]; then
  echo "Refusing to deploy: Lasna RPC chain id $lasna_id is not Lasna ($LASNA_CHAIN)"
  exit 1
fi

sepolia_bal="$(cast balance "$ADDR" --rpc-url "$SEPOLIA_RPC")"
lasna_bal="$(cast balance "$ADDR" --rpc-url "$LASNA_RPC")"
echo "Ethereum Sepolia ETH wei: $sepolia_bal"
echo "Lasna lREACT wei:         $lasna_bal"
if [[ "$sepolia_bal" == "0" || "$lasna_bal" == "0" ]]; then
  echo "Deployer is not funded on both testnets yet."
  exit 2
fi

parse_deployed() {
  python3 -c '
import sys,re,json
t=sys.stdin.read()
# forge --json or text
m=re.search(r"Deployed to:\s*(0x[a-fA-F0-9]{40})", t)
if m:
    print(m.group(1)); raise SystemExit
# json object or lines
for line in t.splitlines():
    line=line.strip()
    if line.startswith("{") and "deployedTo" in line:
        d=json.loads(line)
        print(d.get("deployedTo") or d.get("address") or "")
        raise SystemExit
print("")
print(t, file=sys.stderr)
raise SystemExit("could not parse deployed address")
'
}

echo "== 1/5 PayWatchReactive on Lasna (funded with 0.2 lREACT) =="
REACT_OUT="$(forge create --broadcast --rpc-url "$LASNA_RPC" --private-key "$PRIVATE_KEY" --value 0.2ether \
  src/PayWatchReactive.sol:PayWatchReactive)"
echo "$REACT_OUT"
REACT_ADDR="$(printf '%s\n' "$REACT_OUT" | parse_deployed)"
echo "PayWatchReactive=$REACT_ADDR"
test -n "$REACT_ADDR"

echo "== 2/5 ReceiptRegistry on Ethereum Sepolia (funded with 0.005 ETH) =="
REG_OUT="$(forge create --broadcast --rpc-url "$SEPOLIA_RPC" --private-key "$PRIVATE_KEY" --value 0.005ether \
  src/ReceiptRegistry.sol:ReceiptRegistry --constructor-args "$SEPOLIA_CALLBACK_PROXY" "$REACT_ADDR")"
echo "$REG_OUT"
REG_ADDR="$(printf '%s\n' "$REG_OUT" | parse_deployed)"
echo "ReceiptRegistry=$REG_ADDR"
test -n "$REG_ADDR"

echo "== 3/5 setRegistry =="
cast send "$REACT_ADDR" --rpc-url "$LASNA_RPC" --private-key "$PRIVATE_KEY" \
  "setRegistry(address,uint256)" "$REG_ADDR" "$SEPOLIA_CHAIN"

echo "== 4/5 DemoToken on Ethereum Sepolia =="
TOK_OUT="$(forge create --broadcast --rpc-url "$SEPOLIA_RPC" --private-key "$PRIVATE_KEY" \
  src/DemoToken.sol:DemoToken)"
echo "$TOK_OUT"
TOK_ADDR="$(printf '%s\n' "$TOK_OUT" | parse_deployed)"
echo "DemoToken=$TOK_ADDR"
test -n "$TOK_ADDR"
cast send "$TOK_ADDR" --rpc-url "$SEPOLIA_RPC" --private-key "$PRIVATE_KEY" \
  "mint(address,uint256)" "$ADDR" 1000000000000

echo "== 5/5 addWatch (min 10 pwUSD) =="
MERCHANT="${MERCHANT:-$ADDR}"
MIN="${MIN_AMOUNT:-10000000}"
cast send "$REACT_ADDR" --rpc-url "$LASNA_RPC" --private-key "$PRIVATE_KEY" \
  "addWatch(uint256,address,address,uint256)" "$SEPOLIA_CHAIN" "$TOK_ADDR" "$MERCHANT" "$MIN"

mkdir -p "$ROOT/deployments"
cat > "$ROOT/deployments/11155111-5318007.json" <<JSON
{
  "brand": "FMF Tools",
  "track": "Set It and Forget It",
  "networks": {
    "originAndDestination": {
      "name": "Ethereum Sepolia",
      "chainId": 11155111,
      "callbackProxy": "$SEPOLIA_CALLBACK_PROXY",
      "explorer": "https://sepolia.etherscan.io"
    },
    "reactive": {
      "name": "Reactive Lasna",
      "chainId": 5318007,
      "explorer": "https://lasna.reactscan.net"
    }
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
echo "Wrote deployments/11155111-5318007.json"
echo "Next: ./script/demo-payment.sh"
