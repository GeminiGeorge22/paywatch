# PayWatch demo video (under 3 minutes)

Record after deploy + `./script/demo-payment.sh` have produced the three loop transaction hashes. On-screen brand: FMF Tools. No personal names.

Suggested 2:30 rundown:

0:00–0:20  Title: “PayWatch — payment receipts without a bot.” One sentence: a Transfer to a merchant address becomes an on-chain receipt, and can close an invoice.

0:20–0:50  Architecture diagram from the README (three boxes: token, Lasna watcher, registry). Point at the official Omni calls: subscribe, react, requestCallbackV_1_0.

0:50–1:20  Show `forge test` : 11 passed, 0 failed.

1:20–2:10  Live (or recorded) happy path:
          - registerInvoice for 20 pwUSD
          - transfer 25 pwUSD on Base Sepolia (show the origin tx on Sepolia Basescan)
          - show the Lasna react tx on https://lasna.reactscan.net
          - show ReceiptRegistry PaymentRecorded + InvoicePaid on Basescan
          - `isInvoicePaid` returns true

2:10–2:30  Contract addresses and the three hashes, plus “open source, MIT, FMF Tools.”
