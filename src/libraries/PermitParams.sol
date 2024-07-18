// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

struct ERC20PermitParams {
    uint256 permitAmount;
    PermitSignature signature;
}

struct PermitSignature {
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}

library PermitParamsLibrary {
    function tryPermit(ERC20PermitParams memory params, address token, address from, address to)
        internal
        returns (bool)
    {
        return tryPermit(params.signature, IERC20Permit(token), params.permitAmount, from, to);
    }

    function tryPermit(PermitSignature memory params, IERC20Permit token, uint256 amount, address from, address to)
        internal
        returns (bool)
    {
        if (params.deadline > 0) {
            try token.permit(from, to, amount, params.deadline, params.v, params.r, params.s) {
                return true;
            } catch {}
        }
        return false;
    }
}
