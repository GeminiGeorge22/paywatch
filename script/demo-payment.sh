#!/usr/bin/env bash
# Send a demo payment on Ethereum Sepolia so PayWatch can write a receipt.
set -euo pipefail
export PATH="${HOME}/.foundry/bin:${PATH}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ART="$ROOT/deployments/11155111-5318007.json"
test -f "$ART" || { echo "missing $ART — run script/deploy.sh first"; exit 1; }

if [[ -z "${PRIVATE_KEY:-}" && -f "$ROOT/deployer.key" ]]; then
  PRIVATE_KEY="$(tr -d '[:space:]' < "$ROOT/deployer.key")"
fi
PRIVATE_KEY="${PRIVATE_KEY#0x}"
SEPOLIA_RPC="${SEPOLIA_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"

eval "$(python3 - "$ART" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
c=d["contracts"]
print(f"REG={c['ReceiptRegistry']}")
print(f"TOK={c['DemoToken']}")
print(f"REACT={c['PayWatchReactive']}")
print(f"MERCHANT={d['merchant']}")
PY
)"

echo "ReceiptRegistry=$REG"
echo "DemoToken=$TOK"
echo "PayWatchReactive=$REACT"
echo "merchant=$MERCHANT"

PAYER_ADDR="$(cast wallet address --private-key "$PRIVATE_KEY")"
INV="${INVOICE_ID:-0x$(python3 -c 'import os;print(os.urandom(32).hex())')}"
echo "Registering invoice $INV for 20 pwUSD"
REG_TX="$(cast send "$REG" --rpc-url "$SEPOLIA_RPC" --private-key "$PRIVATE_KEY" \
  "registerInvoice(bytes32,address,uint256,uint256)" "$INV" "$TOK" 20000000 $(( $(date +%s) + 2592000 )) --json)"
echo "$REG_TX"

echo "Sending 25 pwUSD from $PAYER_ADDR to $MERCHANT"
TX="$(cast send "$TOK" --rpc-url "$SEPOLIA_RPC" --private-key "$PRIVATE_KEY" \
  "transfer(address,uint256)" "$MERCHANT" 25000000 --json)"
echo "$TX"
TXHASH="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("transactionHash") or d.get("hash") or "")' <<<"$TX")"
echo "ORIGIN_TRANSFER_TX=$TXHASH"
echo "INVOICE_ID=$INV"

mkdir -p "$ROOT/deployments"
python3 - "$ART" "$TXHASH" "$INV" <<'PY'
import json,sys
art, tx, inv = sys.argv[1], sys.argv[2], sys.argv[3]
d=json.load(open(art))
d.setdefault("loop", {})
d["loop"]["originTransferTx"] = tx
d["loop"]["invoiceId"] = inv
json.dump(d, open(art,"w"), indent=2)
print("updated", art)
PY
echo
echo "Wait for the Lasna react + Sepolia callback, then run script/wait-loop.sh"
