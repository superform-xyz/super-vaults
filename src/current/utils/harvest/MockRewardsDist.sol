// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/// @notice Just give caller 100 E18 tokens
contract MockRewardsDistribution is ERC20 {
    address public immutable manager;
    address public rewardToken;

    constructor(
        string memory name_,
        string memory symbol_,
        address rewardToken_
    ) ERC20(name_, symbol_, 18) {
        manager = msg.sender;
        rewardToken = rewardToken_;
    }

    function getReward() external {
        _mint(msg.sender, 100 ether);
    }
}
