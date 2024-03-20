// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import "../../src/Rebalancer.sol";

contract RebalancerWrapper is Rebalancer {
    constructor(IBookManager _bookManager, address owner_, Rebalancer addressToEtch) Rebalancer(_bookManager, owner_) {
        Hooks.validateHookPermissions(addressToEtch, getHooksCalls());
    }

    // make this a no-op in testing
    function validateHookAddress(BaseHook _this) internal pure override {}
}
