# PayWatch — on-chain payment receipts, no bot

**FMF Tools** entry for the [Reactive Omni Buildathon](https://dorahacks.io/hackathon/reactive-omni-buildathon) track **Set It and Forget It**.

A merchant names an ERC-20 and an address. When a `Transfer` of at least the minimum amount arrives at that address on Ethereum Sepolia, a reactive contract on Lasna requests a callback that writes a receipt on Ethereum Sepolia. Optional invoices are marked paid when a matching receipt lands.

Nothing off-chain has to stay running. That is the product: payment receipts and invoice settlement without a watcher process.

## Why this is useful

Freelancers, x402 merchants, and small on-chain shops should not have to run an indexer or a bot just to know “did this invoice get paid?” PayWatch turns the incoming `Transfer` into a queryable receipt (`ReceiptRegistry`) and can close a pre-registered invoice in the same callback.

The demo token (`pwUSD`, 6 decimals) has the same `Transfer` event shape as USDC, so the same watcher can be pointed at Circle test USDC without a code change.

## Architecture

```
Ethereum Sepolia                      Reactive Lasna                     Ethereum Sepolia
DemoToken / USDC                      PayWatchReactive                   ReceiptRegistry
Transfer(from, merchant, amount)  -->  react() if amount >= min  -->    recordPayment(...)
                                                                       match open invoice
```

- Origin and destination: Ethereum Sepolia (chain ID 11155111). Callback proxy: `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4`.
- Reactive contract: Lasna testnet (chain ID 5318007). System contract: `0x8888888888888888888888888888888888888888`.
- Built against official [reactive-lib-omni](https://github.com/Reactive-Network/reactive-lib-omni) (Omni API: `onlySystem`, `SYSTEM.subscribe`, `SYSTEM.requestCallbackV_1_0`). Not the legacy `vm` / `emit Callback` API.
- `CALLBACK_GAS_LIMIT` is 3,000,000 so the destination proxy has enough gas after its own overhead.

## Live testnet loop

See [`deployments/LOOP.md`](deployments/LOOP.md) for contract addresses and the three transaction hashes.

- Origin Transfer: https://sepolia.etherscan.io/tx/0x9f4836f6454b47bfff78e0eec9f54d005f8581ce38a8b7b1586ad8466713fab0
- Lasna react: https://lasna.reactscan.net/tx/0xbaa1aed71477e43cdafa6d71f09d24de62cfc454d508778fee8b1911e39d738a
- Destination receipt: https://sepolia.etherscan.io/tx/0x5c5907db34e83ae653d7ea8441b0ef549cb1ca8c64801aa5fc229ac655d481cf

## Tests

```bash
# Requires Foundry (https://book.getfoundry.sh)
forge test -vv
```

Expected: 11 passed, 0 failed. Coverage includes subscription filters, minimum-amount gating, the full event → callback → receipt → invoice loop, and rejection of forged or wrong-sender callbacks.

## Deploy (testnets only)

The deploy script refuses any RPC that is not Lasna or Ethereum Sepolia. It will not send mainnet transactions.

```bash
# After the deployer has Ethereum Sepolia ETH:
./script/request-lreact.sh 0.02ether   # 0.02 ETH -> 2 lREACT; keep residual ETH for deploys
./script/deploy.sh
./script/demo-payment.sh
./script/wait-loop.sh
```

`request-lreact.sh` calls `request(address)` on the official Lasna faucet at `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` on Ethereum Sepolia (1 ETH → 100 lREACT, max 5 ETH).

## Contracts

| Contract | Network | Role |
| --- | --- | --- |
| `PayWatchReactive` | Lasna | Owner adds watches; `react()` requests the callback |
| `ReceiptRegistry` | Ethereum Sepolia | Authenticated receipts + invoice matching |
| `DemoToken` | Ethereum Sepolia | 6-decimal ERC-20 for the demo |

## License

MIT. © 2026 FMF Tools.
