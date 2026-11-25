# PayWatch — on-chain payment receipts, no bot

**FMF Tools** entry for the [Reactive Omni Buildathon](https://dorahacks.io/hackathon/reactive-omni-buildathon) track **Set It and Forget It**.

A merchant names an ERC-20 and an address. When a `Transfer` of at least the minimum amount arrives at that address on Base Sepolia, a reactive contract on Lasna requests a callback that writes a receipt on Base Sepolia. Optional invoices are marked paid when a matching receipt lands.

Nothing off-chain has to stay running. That is the product: payment receipts and invoice settlement without a watcher process.

## Why this is useful

Freelancers, x402 merchants, and small on-chain shops should not have to run a indexer or a bot just to know “did this invoice get paid?” PayWatch turns the incoming `Transfer` into a queryable receipt (`ReceiptRegistry`) and can close a pre-registered invoice in the same callback.

The demo token (`pwUSD`, 6 decimals) has the same `Transfer` event shape as USDC, so the same watcher can be pointed at Circle test USDC (`0x036CbD53842c5426634e7929541eC2318f3dCF7e` on Base Sepolia) without a code change.

## Architecture

```
Base Sepolia                          Reactive Lasna                     Base Sepolia
DemoToken / USDC                      PayWatchReactive                   ReceiptRegistry
Transfer(from, merchant, amount)  -->  react() if amount >= min  -->    recordPayment(...)
                                                                       match open invoice
```

- Origin and destination: Base Sepolia (chain ID 84532). Callback proxy: `0x476F44b11F5C942c58f4c8E3d0300E5710743585`.
- Reactive contract: Lasna testnet (chain ID 5318007). System contract: `0x8888888888888888888888888888888888888888`.
- Built against official [reactive-lib-omni](https://github.com/Reactive-Network/reactive-lib-omni) (Omni API: `onlySystem`, `SYSTEM.subscribe`, `SYSTEM.requestCallbackV_1_0`). Not the legacy `vm` / `emit Callback` API.
- Timers, if added later on Base Sepolia, will use timestamps, not block counts (200ms blocks).

## Tests

```bash
# Requires Foundry (https://book.getfoundry.sh)
forge test -vv
```

Expected: 11 passed, 0 failed. Coverage includes subscription filters, minimum-amount gating, the full event → callback → receipt → invoice loop, and rejection of forged or wrong-sender callbacks.

## Deploy (testnets only)

The deploy script refuses any RPC that is not Lasna or Base Sepolia. It will not send mainnet transactions.

```bash
./script/deploy.sh --help
./script/deploy.sh          # creates a gitignored deployer key if needed, then stops for funding
# fund Base Sepolia ETH, then request Lasna lREACT (see script help)
./script/deploy.sh          # deploys all three contracts, setRegistry, addWatch
./script/demo-payment.sh    # register an invoice and send 25 pwUSD
```

After the callback lands, record:

1. Origin `Transfer` transaction hash (Base Sepolia)
2. Reactive `react` / `requestCallbackV_1_0` transaction hash (Lasna)
3. Destination `recordPayment` callback transaction hash (Base Sepolia)

Those three hashes are the “full loop” the judges asked for.

## Contracts

| Contract | Network | Role |
| --- | --- | --- |
| `PayWatchReactive` | Lasna | Owner adds watches; `react()` requests the callback |
| `ReceiptRegistry` | Base Sepolia | Authenticated receipts + invoice matching |
| `DemoToken` | Base Sepolia | 6-decimal ERC-20 for the demo |

## License

MIT. © 2026 FMF Tools.
