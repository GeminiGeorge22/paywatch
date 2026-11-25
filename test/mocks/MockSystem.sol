// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";

/// @notice Test double for the Reactive Omni system contract at 0x888...888.
contract MockSystem is ISystemContract {
    struct Sub {
        uint256 chainId;
        address contractAddr;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
    }

    Sub[] public subs;
    ISystemContract.CallbackConfiguration_V_1_0 public lastCallback;
    uint256 public callbackCount;
    mapping(address => uint256) public debtOf;

    receive() external payable {}

    function debt(address contract_) external view returns (uint256) {
        return debtOf[contract_];
    }

    function setDebt(address contract_, uint256 amount) external {
        debtOf[contract_] = amount;
    }

    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external {
        subs.push(Sub(chainId_, contract_, topic0_, topic1_, topic2_, topic3_));
    }

    function unsubscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external {
        for (uint256 i = 0; i < subs.length; i++) {
            if (
                subs[i].chainId == chainId_ && subs[i].contractAddr == contract_ && subs[i].topic0 == topic0_
                    && subs[i].topic1 == topic1_ && subs[i].topic2 == topic2_ && subs[i].topic3 == topic3_
            ) {
                subs[i] = subs[subs.length - 1];
                subs.pop();
                return;
            }
        }
    }

    function requestCallback(CallbackVersion, bytes memory) external {}

    function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config_) external {
        lastCallback = config_;
        callbackCount++;
    }

    function subCount() external view returns (uint256) {
        return subs.length;
    }
}

/// @notice Test double for a destination-chain callback proxy.
contract MockCallbackProxy is IPayable {
    mapping(address => uint256) public debtOf;

    receive() external payable {}

    function debt(address contract_) external view returns (uint256) {
        return debtOf[contract_];
    }

    /// @dev Mimic the real proxy: overwrite the first ABI argument (after the selector)
    ///      with `reactive_` and call `target`.
    function deliver(address target, address reactive_, bytes memory payload) external returns (bool ok, bytes memory ret) {
        require(payload.length >= 36, "short payload");
        bytes32 word = bytes32(uint256(uint160(reactive_)));
        assembly {
            mstore(add(add(payload, 32), 4), word)
        }
        (ok, ret) = target.call(payload);
        require(ok, string(ret));
    }
}
