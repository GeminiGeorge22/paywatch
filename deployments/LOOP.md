# PayWatch full-loop evidence (Ethereum Sepolia + Lasna)

Brand: FMF Tools. Track: Set It and Forget It.
Deployer: `0x06f155638f5Dc8D4Ff640e7983A57465F781990c`

## Contracts

| Contract | Network | Address |
| --- | --- | --- |
| PayWatchReactive | Reactive Lasna (5318007) | [`0xdaaA8C47606aCBD12688eB272666318DC827B774`](https://lasna.reactscan.net/address/0xdaaA8C47606aCBD12688eB272666318DC827B774) |
| ReceiptRegistry | Ethereum Sepolia (11155111) | [`0x267096a80Ebd127CaEfe4B12bDAf040DfADe5Fd9`](https://sepolia.etherscan.io/address/0x267096a80Ebd127CaEfe4B12bDAf040DfADe5Fd9) |
| DemoToken (pwUSD) | Ethereum Sepolia | [`0x1DfCAE54F2E761c29506F3010Ed3Fe4E4cd4e905`](https://sepolia.etherscan.io/address/0x1DfCAE54F2E761c29506F3010Ed3Fe4E4cd4e905) |

Callback proxy on Ethereum Sepolia: `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4`.

## Full loop

1. Origin `Transfer` (25 pwUSD to the merchant) on Ethereum Sepolia  
   [`0x9f4836f6454b47bfff78e0eec9f54d005f8581ce38a8b7b1586ad8466713fab0`](https://sepolia.etherscan.io/tx/0x9f4836f6454b47bfff78e0eec9f54d005f8581ce38a8b7b1586ad8466713fab0)

2. Lasna `react` + `requestCallbackV_1_0`  
   [`0xbaa1aed71477e43cdafa6d71f09d24de62cfc454d508778fee8b1911e39d738a`](https://lasna.reactscan.net/tx/0xbaa1aed71477e43cdafa6d71f09d24de62cfc454d508778fee8b1911e39d738a)

3. Destination `PaymentRecorded` + `InvoicePaid` on Ethereum Sepolia  
   [`0x5c5907db34e83ae653d7ea8441b0ef549cb1ca8c64801aa5fc229ac655d481cf`](https://sepolia.etherscan.io/tx/0x5c5907db34e83ae653d7ea8441b0ef549cb1ca8c64801aa5fc229ac655d481cf)

`isInvoicePaid(0xad69510e46525c18aefbce02ea24775bb266809a57fb6ed1eb4ea142d51945b6)` returns `true`. `receiptCount` is `1`.

`CALLBACK_GAS_LIMIT` is 3,000,000. An earlier 1,000,000-gas callback ran out of gas on the proxy; these contracts are the redeploy that completed the loop.
