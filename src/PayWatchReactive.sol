// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title PayWatchReactive
/// @notice Lasna-side watcher: subscribes to ERC-20 Transfer events on an origin chain
///         (Base Sepolia) for a merchant address, and requests a callback to ReceiptRegistry
///         when the amount meets the merchant's minimum. This is the "set it and forget it"
///         bot replacement: no off-chain process has to stay online.
contract PayWatchReactive is AbstractReactive {
    /// @dev keccak256("Transfer(address,address,uint256)")
    uint256 internal constant TRANSFER_TOPIC0 =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    uint64 public constant CALLBACK_GAS_LIMIT = 3_000_000;

    struct Watch {
        uint256 originChainId;
        address token;
        address merchant;
        uint256 minAmount;
        bool active;
    }

    address public owner;
    uint256 public destinationChainId;
    address public receiptRegistry;

    mapping(bytes32 => Watch) public watches;
    bytes32[] public watchIds;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RegistrySet(address indexed registry, uint256 destinationChainId);
    event WatchAdded(
        bytes32 indexed watchId, uint256 originChainId, address token, address merchant, uint256 minAmount
    );
    event WatchRemoved(bytes32 indexed watchId);
    event PaymentDetected(
        bytes32 indexed watchId,
        address payer,
        address merchant,
        uint256 amount,
        uint256 originChainId,
        bytes32 originTxHash
    );

    error NotOwner();
    error ZeroAddress();
    error WatchExists();
    error WatchNotFound();
    error RegistryNotSet();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() payable {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Set after ReceiptRegistry is deployed on the destination chain.
    function setRegistry(address registry, uint256 destinationChainId_) external onlyOwner {
        if (registry == address(0)) revert ZeroAddress();
        receiptRegistry = registry;
        destinationChainId = destinationChainId_;
        emit RegistrySet(registry, destinationChainId_);
    }

    /// @notice Start watching Transfer events of `token` whose `to` is `merchant`.
    function addWatch(uint256 originChainId, address token, address merchant, uint256 minAmount)
        external
        onlyOwner
        returns (bytes32 watchId)
    {
        if (token == address(0) || merchant == address(0)) revert ZeroAddress();
        watchId = keccak256(abi.encode(originChainId, token, merchant));
        if (watches[watchId].active) revert WatchExists();

        watches[watchId] = Watch({
            originChainId: originChainId,
            token: token,
            merchant: merchant,
            minAmount: minAmount,
            active: true
        });
        watchIds.push(watchId);

        SYSTEM.subscribe(
            originChainId,
            token,
            TRANSFER_TOPIC0,
            REACTIVE_IGNORE,
            uint256(uint160(merchant)),
            REACTIVE_IGNORE
        );

        emit WatchAdded(watchId, originChainId, token, merchant, minAmount);
    }

    function removeWatch(bytes32 watchId) external onlyOwner {
        Watch storage w = watches[watchId];
        if (!w.active) revert WatchNotFound();
        w.active = false;
        SYSTEM.unsubscribe(
            w.originChainId,
            w.token,
            TRANSFER_TOPIC0,
            REACTIVE_IGNORE,
            uint256(uint160(w.merchant)),
            REACTIVE_IGNORE
        );
        emit WatchRemoved(watchId);
    }

    function coverDebt() external {
        _coverDebt();
    }

    function watchCount() external view returns (uint256) {
        return watchIds.length;
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        if (receiptRegistry == address(0)) revert RegistryNotSet();
        if (log_.topic0 != TRANSFER_TOPIC0) return;

        address token = log_.contractAddress;
        address payer = address(uint160(log_.topic1));
        address merchant = address(uint160(log_.topic2));
        bytes32 watchId = keccak256(abi.encode(log_.chainId, token, merchant));
        Watch storage w = watches[watchId];
        if (!w.active) return;

        uint256 amount = abi.decode(log_.data, (uint256));
        if (amount < w.minAmount) return;

        bytes32 originTxHash = bytes32(log_.txHash);
        emit PaymentDetected(watchId, payer, merchant, amount, log_.chainId, originTxHash);

        bytes memory payload = abi.encodeWithSelector(
            bytes4(keccak256("recordPayment(address,address,address,address,uint256,uint256,bytes32,uint256,uint256)")),
            address(0), // overwritten by the callback proxy with this reactive contract
            merchant,
            token,
            payer,
            amount,
            log_.chainId,
            originTxHash,
            log_.blockNumber,
            log_.logIndex
        );

        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destinationChainId,
                recipient: receiptRegistry,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }
}
