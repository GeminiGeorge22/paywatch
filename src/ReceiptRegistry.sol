// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

/// @title ReceiptRegistry
/// @notice Destination-chain registry of on-chain payment receipts, written by a Reactive
///         callback when a watched ERC-20 Transfer arrives at a merchant address.
///         Merchants can also register invoices that are marked paid when a matching
///         receipt lands. No off-chain bot is required.
contract ReceiptRegistry is AbstractCallback {
    struct Receipt {
        address merchant;
        address token;
        address payer;
        uint256 amount;
        uint256 originChainId;
        bytes32 originTxHash;
        uint256 originBlock;
        uint256 logIndex;
        uint256 recordedAt;
        bytes32 matchedInvoiceId;
    }

    struct Invoice {
        address merchant;
        address token;
        uint256 amount;
        uint256 expiry;
        bool paid;
        bytes32 receiptId;
        uint256 createdAt;
    }

    event InvoiceRegistered(
        bytes32 indexed invoiceId,
        address indexed merchant,
        address indexed token,
        uint256 amount,
        uint256 expiry
    );

    event PaymentRecorded(
        bytes32 indexed receiptId,
        address indexed merchant,
        address indexed token,
        address payer,
        uint256 amount,
        uint256 originChainId,
        bytes32 originTxHash,
        uint256 originBlock,
        uint256 logIndex
    );

    event InvoicePaid(bytes32 indexed invoiceId, bytes32 indexed receiptId, address merchant);

    error AlreadyRecorded(bytes32 receiptId);
    error InvoiceExists(bytes32 invoiceId);
    error ZeroAmount();

    uint256 public receiptCount;
    mapping(bytes32 => Receipt) public receipts;
    mapping(bytes32 => Invoice) public invoices;
    mapping(address => bytes32[]) public receiptsByMerchant;
    mapping(address => bytes32[]) public invoicesByMerchant;

    constructor(IPayable callbackProxy_, address callbackSender_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {}

    /// @notice Register an invoice that should be marked paid when a matching transfer is receipted.
    function registerInvoice(bytes32 invoiceId, address token, uint256 amount, uint256 expiry)
        external
        returns (bytes32)
    {
        if (amount == 0) revert ZeroAmount();
        if (invoiceId == bytes32(0)) {
            invoiceId = keccak256(
                abi.encode(msg.sender, token, amount, expiry, block.timestamp, invoicesByMerchant[msg.sender].length)
            );
        }
        if (invoices[invoiceId].merchant != address(0)) revert InvoiceExists(invoiceId);

        invoices[invoiceId] = Invoice({
            merchant: msg.sender,
            token: token,
            amount: amount,
            expiry: expiry,
            paid: false,
            receiptId: bytes32(0),
            createdAt: block.timestamp
        });
        invoicesByMerchant[msg.sender].push(invoiceId);
        emit InvoiceRegistered(invoiceId, msg.sender, token, amount, expiry);
        return invoiceId;
    }

    /// @notice Callback from Reactive Network. First argument is overwritten by the proxy
    ///         with the reactive contract that requested the callback.
    function recordPayment(
        address reactive_,
        address merchant,
        address token,
        address payer,
        uint256 amount,
        uint256 originChainId,
        bytes32 originTxHash,
        uint256 originBlock,
        uint256 logIndex
    )
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
        returns (bytes32 receiptId)
    {
        receiptId = keccak256(abi.encode(originChainId, originTxHash, logIndex));
        if (receipts[receiptId].recordedAt != 0) revert AlreadyRecorded(receiptId);

        bytes32 matched = _matchInvoice(merchant, token, amount);
        receipts[receiptId] = Receipt({
            merchant: merchant,
            token: token,
            payer: payer,
            amount: amount,
            originChainId: originChainId,
            originTxHash: originTxHash,
            originBlock: originBlock,
            logIndex: logIndex,
            recordedAt: block.timestamp,
            matchedInvoiceId: matched
        });
        receiptsByMerchant[merchant].push(receiptId);
        unchecked {
            receiptCount++;
        }

        emit PaymentRecorded(
            receiptId, merchant, token, payer, amount, originChainId, originTxHash, originBlock, logIndex
        );

        if (matched != bytes32(0)) {
            invoices[matched].paid = true;
            invoices[matched].receiptId = receiptId;
            emit InvoicePaid(matched, receiptId, merchant);
        }
    }

    function coverDebt() external {
        _coverDebt();
    }

    function getReceipt(bytes32 receiptId) external view returns (Receipt memory) {
        return receipts[receiptId];
    }

    function getInvoice(bytes32 invoiceId) external view returns (Invoice memory) {
        return invoices[invoiceId];
    }

    function merchantReceiptCount(address merchant) external view returns (uint256) {
        return receiptsByMerchant[merchant].length;
    }

    function isInvoicePaid(bytes32 invoiceId) external view returns (bool) {
        return invoices[invoiceId].paid;
    }

    function _matchInvoice(address merchant, address token, uint256 amount)
        internal
        view
        returns (bytes32)
    {
        bytes32[] storage list = invoicesByMerchant[merchant];
        uint256 len = list.length;
        for (uint256 i = 0; i < len; i++) {
            Invoice storage inv = invoices[list[i]];
            if (inv.paid) continue;
            if (inv.token != token) continue;
            if (inv.expiry != 0 && block.timestamp > inv.expiry) continue;
            if (amount >= inv.amount) return list[i];
        }
        return bytes32(0);
    }
}
