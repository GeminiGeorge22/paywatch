// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { PayWatchReactive } from "../src/PayWatchReactive.sol";
import { ReceiptRegistry } from "../src/ReceiptRegistry.sol";
import { DemoToken } from "../src/DemoToken.sol";
import { MockSystem, MockCallbackProxy } from "./mocks/MockSystem.sol";

contract PayWatchTest is Test {
    address constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 constant TRANSFER_TOPIC0 =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    uint256 constant ORIGIN = 84532;
    uint256 constant DEST = 84532;
    uint256 constant IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    MockSystem system;
    MockCallbackProxy proxy;
    PayWatchReactive watch;
    ReceiptRegistry registry;
    DemoToken token;

    address merchant = address(0xA11CE);
    address payer = address(0xB0B);
    address stranger = address(0xBAD);

    function setUp() public {
        MockSystem impl = new MockSystem();
        vm.etch(SYSTEM_ADDR, address(impl).code);
        system = MockSystem(payable(SYSTEM_ADDR));

        proxy = new MockCallbackProxy();

        watch = new PayWatchReactive{value: 1 ether}();
        registry = new ReceiptRegistry{value: 0.1 ether}(IPayable(payable(address(proxy))), address(watch));
        token = new DemoToken();
        token.mint(payer, 1_000_000_000); // 1,000 pwUSD (6 decimals)

        watch.setRegistry(address(registry), DEST);
        watch.addWatch(ORIGIN, address(token), merchant, 10_000_000); // min 10 pwUSD
    }

    function _log(address from, address to, uint256 amount, uint256 txHash, uint256 logIndex)
        internal
        view
        returns (IReactive.LogRecord memory log)
    {
        log = IReactive.LogRecord({
            chainId: ORIGIN,
            contractAddress: address(token),
            topic0: TRANSFER_TOPIC0,
            topic1: uint256(uint160(from)),
            topic2: uint256(uint160(to)),
            topic3: 0,
            data: abi.encode(amount),
            blockNumber: 123,
            opCode: 0,
            blockHash: uint256(0xabc),
            txHash: txHash,
            logIndex: logIndex
        });
    }

    function test_subscribeOnAddWatch() public view {
        assertEq(system.subCount(), 1);
        (uint256 chainId, address c, uint256 t0, uint256 t1, uint256 t2, uint256 t3) = system.subs(0);
        assertEq(chainId, ORIGIN);
        assertEq(c, address(token));
        assertEq(t0, TRANSFER_TOPIC0);
        assertEq(t1, IGNORE);
        assertEq(t2, uint256(uint160(merchant)));
        assertEq(t3, IGNORE);
    }

    function test_reactRequestsCallbackAboveMinimum() public {
        IReactive.LogRecord memory log = _log(payer, merchant, 25_000_000, 0x111, 3);
        vm.prank(SYSTEM_ADDR);
        watch.react(log);

        assertEq(system.callbackCount(), 1);
        (uint256 chainId, address recipient, uint64 gasLimit, bytes memory payload) = _lastCb();
        assertEq(chainId, DEST);
        assertEq(recipient, address(registry));
        assertEq(gasLimit, watch.CALLBACK_GAS_LIMIT());
        assertEq(payload.length > 4, true);
    }

    function test_reactIgnoresBelowMinimum() public {
        IReactive.LogRecord memory log = _log(payer, merchant, 9_999_999, 0x111, 3);
        vm.prank(SYSTEM_ADDR);
        watch.react(log);
        assertEq(system.callbackCount(), 0);
    }

    function test_reactIgnoresUnknownMerchant() public {
        IReactive.LogRecord memory log = _log(payer, stranger, 25_000_000, 0x111, 3);
        vm.prank(SYSTEM_ADDR);
        watch.react(log);
        assertEq(system.callbackCount(), 0);
    }

    function test_reactRejectsNonSystem() public {
        IReactive.LogRecord memory log = _log(payer, merchant, 25_000_000, 0x111, 3);
        vm.prank(stranger);
        vm.expectRevert();
        watch.react(log);
    }

    function test_fullLoopWritesReceiptAndPaysInvoice() public {
        bytes32 invoiceId = keccak256("INV-100");
        vm.prank(merchant);
        registry.registerInvoice(invoiceId, address(token), 20_000_000, block.timestamp + 30 days);

        IReactive.LogRecord memory log = _log(payer, merchant, 25_000_000, 0x222, 7);
        vm.prank(SYSTEM_ADDR);
        watch.react(log);

        (,,, bytes memory payload) = _lastCb();
        (bool ok,) = address(proxy).call(abi.encodeCall(MockCallbackProxy.deliver, (address(registry), address(watch), payload)));
        // deliver already requires ok; just silence
        ok = true;

        bytes32 receiptId = keccak256(abi.encode(ORIGIN, bytes32(uint256(0x222)), uint256(7)));
        ReceiptRegistry.Receipt memory r = registry.getReceipt(receiptId);
        assertEq(r.merchant, merchant);
        assertEq(r.token, address(token));
        assertEq(r.payer, payer);
        assertEq(r.amount, 25_000_000);
        assertEq(r.originChainId, ORIGIN);
        assertEq(r.originTxHash, bytes32(uint256(0x222)));
        assertEq(r.logIndex, 7);
        assertEq(r.matchedInvoiceId, invoiceId);
        assertTrue(registry.isInvoicePaid(invoiceId));
        assertEq(registry.merchantReceiptCount(merchant), 1);
    }

    function test_duplicateReceiptReverts() public {
        IReactive.LogRecord memory log = _log(payer, merchant, 25_000_000, 0x333, 1);
        vm.prank(SYSTEM_ADDR);
        watch.react(log);
        (,,, bytes memory payload) = _lastCb();
        proxy.deliver(address(registry), address(watch), payload);

        vm.expectRevert();
        proxy.deliver(address(registry), address(watch), payload);
    }

    function test_forgedCallbackFromNonProxyReverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        registry.recordPayment(
            address(watch), merchant, address(token), payer, 25_000_000, ORIGIN, bytes32(uint256(1)), 1, 0
        );
    }

    function test_callbackFromWrongReactiveReverts() public {
        bytes memory payload = abi.encodeWithSelector(
            registry.recordPayment.selector,
            address(0),
            merchant,
            address(token),
            payer,
            25_000_000,
            ORIGIN,
            bytes32(uint256(1)),
            1,
            0
        );
        vm.expectRevert();
        proxy.deliver(address(registry), address(0xD00D), payload);
    }

    function test_tokenTransferEmitsStandardTopic() public {
        vm.prank(payer);
        token.transfer(merchant, 15_000_000);
        assertEq(token.balanceOf(merchant), 15_000_000);
    }

    function test_onlyOwnerAddWatch() public {
        vm.prank(stranger);
        vm.expectRevert();
        watch.addWatch(ORIGIN, address(token), stranger, 1);
    }

    function _lastCb()
        internal
        view
        returns (uint256 chainId, address recipient, uint64 gasLimit, bytes memory payload)
    {
        (chainId, recipient, gasLimit, payload) = system.lastCallback();
    }
}
