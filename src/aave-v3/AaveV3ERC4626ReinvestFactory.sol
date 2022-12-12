// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {IPool} from "./external/IPool.sol";
import {AaveV3ERC4626Reinvest} from "./AaveV3ERC4626Reinvest.sol";
import {IRewardsController} from "./external/IRewardsController.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

/// @title AaveV3ERC4626Factory forked from @author zefram.eth
/// @notice Factory for creating AaveV3ERC4626 contracts
contract AaveV3ERC4626ReinvestFactory {
    using Bytes32AddressLib for bytes32;

    /// @notice Manager for setting swap routes for harvest() per each vault
    address public manager;

    /// @notice Mapping of vaults by asset
    mapping(address => AaveV3ERC4626Reinvest) public vaults;

    /// @notice Emitted when a new ERC4626 vault has been created
    /// @param asset The base asset used by the vault
    /// @param vault The vault that was created
    event CreateERC4626Reinvest(
        ERC20 indexed asset,
        AaveV3ERC4626Reinvest vault
    );

    /// @notice Emitted when rewards for a given aToken vault have been set
    event RewardsSetERC4626Reinvest(AaveV3ERC4626Reinvest vault);

    /// @notice Emitted when swap routes have been set for a given aToken vault
    event RoutesSetERC4626Reinvest(AaveV3ERC4626Reinvest vault);

    /// @notice Emitted when harvest has been called for a given aToken vault
    event HarvestERC4626Reinvest(AaveV3ERC4626Reinvest vault);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Thrown when trying to deploy an AaveV3ERC4626 vault using an asset without an aToken
    error AaveV3ERC4626Factory__ATokenNonexistent();

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The Aave Pool contract
    IPool public immutable lendingPool;

    /// @notice The Aave RewardsController contract
    IRewardsController public immutable rewardsController;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        IPool lendingPool_,
        IRewardsController rewardsController_,
        address manager_
    ) {
        lendingPool = lendingPool_;
        rewardsController = rewardsController_;

        /// @dev manager is only used for setting swap routes
        manager = manager_;
    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    function createERC4626(ERC20 asset)
        external
        virtual
        returns (AaveV3ERC4626Reinvest vault)
    {
        require(msg.sender == manager, "onlyOwner");
        IPool.ReserveData memory reserveData = lendingPool.getReserveData(
            address(asset)
        );
        address aTokenAddress = reserveData.aTokenAddress;
        if (aTokenAddress == address(0)) {
            revert AaveV3ERC4626Factory__ATokenNonexistent();
        }

        vault = new AaveV3ERC4626Reinvest(
            asset,
            ERC20(aTokenAddress),
            lendingPool,
            rewardsController,
            address(this)
        );

        vaults[address(asset)] = vault;

        emit CreateERC4626Reinvest(asset, vault);
    }

    /// @notice Get all rewards from AAVE market
    /// @dev Call before setting routes
    /// @dev Requires manual management of Routes
    function setRewards(AaveV3ERC4626Reinvest vault_)
        external
        returns (address[] memory rewards)
    {
        require(msg.sender == manager, "onlyOwner");
        rewards = vault_.setRewards();

        emit RewardsSetERC4626Reinvest(vault_);
    }

    /// @notice Set swap routes for selling rewards
    /// @dev Centralizes setRoutes on all createERC4626 deployments
    function setRoutes(
        AaveV3ERC4626Reinvest vault_,
        address rewardToken,
        address token,
        address pair1,
        address pair2
    ) external {
        require(msg.sender == manager, "onlyOwner");
        vault_.setRoutes(rewardToken, token, pair1, pair2);

        emit RoutesSetERC4626Reinvest(vault_);
    }

    /// @notice Harvest rewards from specified vault
    function harvestFrom(AaveV3ERC4626Reinvest vault_) external {
        vault_.harvest();
        emit HarvestERC4626Reinvest(vault_);
    }
}
