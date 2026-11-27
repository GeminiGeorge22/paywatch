# DoraHacks form values — Reactive Omni Buildathon

Submit at: https://dorahacks.io/hackathon/reactive-omni-buildathon

- Team / builder name: `FMF Tools`
- Email: `fmf-tools@agentmail.to`
- Wallet for prize payout: `0xB2070a4A874E7141E551890a3642bF7B24a1a148`
- Track: `Set It and Forget It`
- Project name: `PayWatch`
- One-line: `On-chain ERC-20 payment receipts and invoice settlement, with no off-chain bot.`
- Public repository URL: `https://github.com/GeminiGeorge22/paywatch`
- Description (paste):

  PayWatch watches ERC-20 Transfer events on Ethereum Sepolia for a merchant address. When a transfer meets the merchant’s minimum, a reactive contract on Lasna requests a callback that writes a receipt to ReceiptRegistry on Ethereum Sepolia and, if one matches, marks an invoice paid. Merchants query receipts on-chain. The demo uses a 6-decimal token with the same event shape as USDC. Built during the event on Lasna + Ethereum Sepolia using the Omni API (subscribe + requestCallbackV_1_0). Public MIT repo, tests included, full loop verified on testnets.

- Deployed contract addresses:
  - PayWatchReactive (Lasna): `0xdaaA8C47606aCBD12688eB272666318DC827B774`
  - ReceiptRegistry (Ethereum Sepolia): `0x267096a80Ebd127CaEfe4B12bDAf040DfADe5Fd9`
  - DemoToken (Ethereum Sepolia): `0x1DfCAE54F2E761c29506F3010Ed3Fe4E4cd4e905`
- Full-loop transaction hashes:
  - Origin Transfer (Ethereum Sepolia): `0x9f4836f6454b47bfff78e0eec9f54d005f8581ce38a8b7b1586ad8466713fab0` — https://sepolia.etherscan.io/tx/0x9f4836f6454b47bfff78e0eec9f54d005f8581ce38a8b7b1586ad8466713fab0
  - Lasna react: `0xbaa1aed71477e43cdafa6d71f09d24de62cfc454d508778fee8b1911e39d738a` — https://lasna.reactscan.net/tx/0xbaa1aed71477e43cdafa6d71f09d24de62cfc454d508778fee8b1911e39d738a
  - Destination receipt (Ethereum Sepolia): `0x5c5907db34e83ae653d7ea8441b0ef549cb1ca8c64801aa5fc229ac655d481cf` — https://sepolia.etherscan.io/tx/0x5c5907db34e83ae653d7ea8441b0ef549cb1ca8c64801aa5fc229ac655d481cf
- Demo video (< 3 minutes): `paywatch-demo.mp4` (generated after the live loop; kept outside this repo). Upload that file on the DoraHacks form.
