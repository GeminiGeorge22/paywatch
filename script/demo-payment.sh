#!/usr/bin/env bash
# Send a demo payment on Base Sepolia so PayWatch can write a receipt.
set -euo pipefail
export PATH="${HOME}/.foundry/bin:${PATH}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ART="$ROOT/deployments/84532-5318007.json"
test -f "$ART" || { echo "missing $ART — run script/deploy.sh first"; exit 1; }

PRIVATE_KEY="${PRIVATE_KEY:-}"
if [[ -z "$PRIVATE_KEY" && -f "$ROOT/deployer.key" ]]; then
  PRIVATE_KEY="$(tr -d '[:space:]' < "$ROOT/deployer.key")"
fi
PRIVATE_KEY="${PRIVATE_KEY#0x}"
BASE_RPC="${BASE_RPC:-https://sepolia.base.org}"

python3 - "$ART" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
for k,v in d["contracts"].items():
    print(f"{k}={v}")
print(f"merchant={d['merchant']}")
PY

eval "$(python3 - "$ART" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
c=d["contracts"]
print(f"REG={c['ReceiptRegistry']}")
print(f"TOK={c['DemoToken']}")
print(f"MERCHANT={d['merchant']}")
PY
)"

PAYER_ADDR="$(cast wallet address --private-key "$PRIVATE_KEY")"
INV="${INVOICE_ID:-0x$(python3 -c 'import os;print(os.urandom(32).hex())')}"
echo "Registering invoice $INV for 20 pwUSD as $MERCHANT"
# If the deployer is the merchant, this works. Otherwise the merchant must send it.
cast send "$REG" --rpc-url "$BASE_RPC" --private-key "$PRIVATE_KEY" \
  "registerInvoice(bytes32,address,uint256,uint256)" "$INV" "$TOK" 20000000 $(( $(date +%s) + 2592000 ))

echo "Sending 25 pwUSD from $PAYER_ADDR to $MERCHANT"
TX=$(cast send "$TOK" --rpc-url "$BASE_RPC" --private-key "$PRIVATE_KEY" \
  "transfer(address,uint256)" "$MERCHANT" 25000000 --json)
echo "$TX"
TXHASH=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("transactionHash") or json.load(open("/dev/stdin")))' <<<"$TX" 2>/dev/null || echo "$TX" | awk '/transactionHash|txHash|0x[a-fA-F0-9]{64}/{print; exit}')
echo "ORIGIN_TRANSFER_TX=$TXHASH"
echo
echo "Wait ~1-2 minutes for the Lasna react + Base Sepolia callback."
echo "Then:"
echo "  cast logs --rpc-url $BASE_RPC --address $REG --from-block latest-200"
echo "  Explore ReceiptRegistry $REG on https://sepolia.basescan.org/address/$REG"
echo "  Explore PayWatchReactive on https://lasna.reactscan.net/"
echo "Save the origin transfer hash, the Lasna react tx, and the Base callback tx in deployments/G4-loop.md"
