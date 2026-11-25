#!/usr/bin/env bash
# Poll for the PayWatch full loop after demo-payment.sh.
set -euo pipefail
export PATH="${HOME}/.foundry/bin:${PATH}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ART="$ROOT/deployments/11155111-5318007.json"
SEPOLIA_RPC="${SEPOLIA_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
PAYMENT_RECORDED="${PAYMENT_RECORDED_TOPIC:-}"
PAYMENT_DETECTED="${PAYMENT_DETECTED_TOPIC:-}"

eval "$(python3 - "$ART" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
c=d["contracts"]
loop=d.get("loop") or {}
print(f"REG={c['ReceiptRegistry']}")
print(f"REACT={c['PayWatchReactive']}")
print(f"ORIGIN={loop.get('originTransferTx') or ''}")
PY
)"

PAYMENT_RECORDED="$(cast keccak 'PaymentRecorded(bytes32,address,address,address,uint256,uint256,bytes32,uint256,uint256)')"
PAYMENT_DETECTED="$(cast keccak 'PaymentDetected(bytes32,address,address,uint256,uint256,bytes32)')"

echo "Waiting for loop. origin=$ORIGIN registry=$REG reactive=$REACT"
SEPOLIA_START="$(cast block-number --rpc-url "$SEPOLIA_RPC")"
LASNA_START="$(cast block-number --rpc-url "$LASNA_RPC")"
# look a little back in case the transfer already happened
SEPOLIA_FROM=$((SEPOLIA_START>200 ? SEPOLIA_START-200 : 0))
LASNA_FROM=$((LASNA_START>2000 ? LASNA_START-2000 : 0))

DEST=""
REACT_TX=""
for i in $(seq 1 40); do
  echo "poll $i ..."
  if [[ -z "$DEST" ]]; then
    DEST_LOGS="$(cast logs --rpc-url "$SEPOLIA_RPC" --address "$REG" --from-block "$SEPOLIA_FROM" --to-block latest "$PAYMENT_RECORDED" --json 2>/dev/null || true)"
    DEST="$(python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)
items=d if isinstance(d,list) else [d]
for x in items:
    h=x.get("transactionHash") or x.get("transaction_hash")
    if h:
        print(h); break
' <<<"$DEST_LOGS")"
  fi
  if [[ -z "$REACT_TX" ]]; then
    REACT_LOGS="$(cast logs --rpc-url "$LASNA_RPC" --address "$REACT" --from-block "$LASNA_FROM" --to-block latest "$PAYMENT_DETECTED" --json 2>/dev/null || true)"
    REACT_TX="$(python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)
items=d if isinstance(d,list) else [d]
for x in items:
    h=x.get("transactionHash") or x.get("transaction_hash")
    if h:
        print(h); break
' <<<"$REACT_LOGS")"
  fi
  echo "  dest=$DEST"
  echo "  lasna=$REACT_TX"
  if [[ -n "$DEST" && -n "$REACT_TX" ]]; then
    break
  fi
  sleep 15
done

python3 - "$ART" "$ORIGIN" "$REACT_TX" "$DEST" <<'PY'
import json,sys
art, origin, lasna, dest = sys.argv[1:5]
d=json.load(open(art))
d.setdefault("loop", {})
d["loop"]["originTransferTx"]=origin or d["loop"].get("originTransferTx")
d["loop"]["lasnaReactTx"]=lasna
d["loop"]["destinationReceiptTx"]=dest
d["loop"]["explorers"]={
  "originTransfer": f"https://sepolia.etherscan.io/tx/{d['loop']['originTransferTx']}" if d["loop"].get("originTransferTx") else None,
  "lasnaReact": f"https://lasna.reactscan.net/tx/{lasna}" if lasna else None,
  "destinationReceipt": f"https://sepolia.etherscan.io/tx/{dest}" if dest else None,
}
json.dump(d, open(art,"w"), indent=2)
print(json.dumps(d["loop"], indent=2))
PY

if [[ -z "$DEST" || -z "$REACT_TX" ]]; then
  echo "LOOP INCOMPLETE"
  exit 2
fi
echo "LOOP COMPLETE"
