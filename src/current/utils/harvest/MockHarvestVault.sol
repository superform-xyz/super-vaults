// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Harvester} from "./Harvester.sol";

/// @notice MockHarvestVault - Demo Vault for implementing reinvesting logic with swap on Uni V2
contract MockHarvestVault is ERC4626 {
    address public immutable manager;
    address public rewardToken;

    Harvester public harvester;

    constructor(
        ERC20 asset_,
        string memory name_,
        string memory symbol_,
        address rewardToken_
    ) ERC4626(asset_, name_, symbol_) {
        manager = msg.sender;
        rewardToken = rewardToken_;
    }

    function enableHarvest() external {
        require(msg.sender == manager, "onlyOwner");
        harvester = new Harvester(manager);
        ERC20(rewardToken).approve(address(harvester), type(uint256).max);
    }

    function claim() external {
        /// Reinvest call
        harvester.harvest();
    }

    function totalAssets() public view override returns (uint256) {}
}
