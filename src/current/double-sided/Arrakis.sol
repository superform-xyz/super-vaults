// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract ArrakisWrapperERC4626 is ERC4626 {
    address public immutable manager;
    constructor(
        ERC20 asset_,
        string memory name_,
        string memory symbol_
    ) ERC4626(asset_, name_, symbol_) {
        manager = msg.sender;
    }

    function totalAssets() public view override returns (uint256) {}
}
