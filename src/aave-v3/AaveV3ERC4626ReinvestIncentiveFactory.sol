// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {IPool} from "./external/IPool.sol";
import {AaveV3ERC4626ReinvestIncentive} from "./AaveV3ERC4626ReinvestIncentive.sol";
import {IRewardsController} from "./external/IRewardsController.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

/// @title AaveV3ERC4626Factory forked from @author zefram.eth
/// @notice Factory for creating AaveV3ERC4626 contracts
contract AaveV3ERC4626ReinvestIncentiveFactory {
    /*//////////////////////////////////////////////////////////////
                        LIBRARIES USAGE
    //////////////////////////////////////////////////////////////*/
    using Bytes32AddressLib for bytes32;

    /*//////////////////////////////////////////////////////////////
                        VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Manager for setting swap routes for harvest() per each vault
    address public manager;

    /// @notice Mapping of vaults by asset
    mapping(address => AaveV3ERC4626ReinvestIncentive) public vaults;

    /*//////////////////////////////////////////////////////////////
                      EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new ERC4626 vault has been created
    /// @param asset The base asset used by the vault
    /// @param vault The vault that was created
    event CreateERC4626Reinvest(
        ERC20 indexed asset,
        AaveV3ERC4626ReinvestIncentive vault
    );

    /// @notice Emitted when rewards for a given aToken vault have been set
    event RewardsSetERC4626Reinvest(AaveV3ERC4626ReinvestIncentive vault);

    /// @notice Emitted when swap routes have been set for a given aToken vault
    event RoutesSetERC4626Reinvest(AaveV3ERC4626ReinvestIncentive vault);

    /// @notice Emitted when harvest has been called for a given aToken vault
    event HarvestERC4626Reinvest(AaveV3ERC4626ReinvestIncentive vault);

    /// @notice Emitted when minTokensToReinvest has been updated for a given aToken vault
    event UpdateMinTokensToReinvest(AaveV3ERC4626ReinvestIncentive vault, uint256 minTokensToHarvest);

    /// @notice Emitted when reinvestRewardBps has been updated for a given aToken vault
    event UpdateReinvestRewardBps(AaveV3ERC4626ReinvestIncentive vault, uint256 reinvestRewardBps);

    /*//////////////////////////////////////////////////////////////
                      ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to deploy an AaveV3ERC4626 vault using an asset without an aToken
    error AaveV3ERC4626Factory__ATokenNonexistent();
    /// @notice Thrown when trying to call a permissioned function with an invalid access
    error INVALID_ACCESS();
    /// @notice Thrown when reinvest reward bps is too high
    error REINVEST_BPS_TOO_HIGH();

    /*//////////////////////////////////////////////////////////////
                      IMMUATABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The Aave Pool contract
    IPool public immutable lendingPool;

    /// @notice The Aave RewardsController contract
    IRewardsController public immutable rewardsController;

    /*//////////////////////////////////////////////////////////////
                      CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Construct a new AaveV3ERC4626Factory
    /// @param lendingPool_ The Aave Pool contract
    /// @param rewardsController_ The Aave RewardsController contract
    /// @param manager_ The manager for setting swap routes
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

    /*//////////////////////////////////////////////////////////////
                      EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new AaveV3ERC4626 vault
    /// @param asset_ The base asset used by the vault
    function createERC4626(ERC20 asset_)
        external
        virtual
        returns (AaveV3ERC4626ReinvestIncentive vault)
    {
        if (msg.sender != manager) revert INVALID_ACCESS();
        IPool.ReserveData memory reserveData = lendingPool.getReserveData(
            address(asset_)
        );
        address aTokenAddress = reserveData.aTokenAddress;
        if (aTokenAddress == address(0)) {
            revert AaveV3ERC4626Factory__ATokenNonexistent();
        }

        vault = new AaveV3ERC4626ReinvestIncentive(
            asset_,
            ERC20(aTokenAddress),
            lendingPool,
            rewardsController,
            address(this)
        );

        vaults[address(asset_)] = vault;

        /// @dev TODO: Seed initial deposit, requires approve to factory
        // init(vault, initAmount);

        emit CreateERC4626Reinvest(asset_, vault);
    }

    /// @notice Get all rewards from AAVE market
    /// @dev Call before setting routes
    /// @dev Requires manual management of Routes
    /// @param vault_ The vault to harvest rewards from
    function setRewards(AaveV3ERC4626ReinvestIncentive vault_)
        external
        returns (address[] memory rewards)
    {
        if (msg.sender != manager) revert INVALID_ACCESS();
        rewards = vault_.setRewards();

        emit RewardsSetERC4626Reinvest(vault_);
    }

    /// @notice Set swap routes for selling rewards
    /// @dev Centralizes setRoutes on all createERC4626 deployments
    /// @param vault_ The vault to set routes for
    /// @param rewardToken_ The reward token address
    /// @param token_ The token to swap to
    /// @param pair1_ The first pair to swap for token_
    /// @param pair2_ The second pair to swap from token_ to asset_
    function setRoutes(
        AaveV3ERC4626ReinvestIncentive vault_,
        address rewardToken_,
        address token_,
        address pair1_,
        address pair2_
    ) external {
        if (msg.sender != manager) revert INVALID_ACCESS();
        vault_.setRoutes(rewardToken_, token_, pair1_, pair2_);

        emit RoutesSetERC4626Reinvest(vault_);
    }

    /// @notice Update minTokensToReinvest
    /// @param vault_ The vault to update
    /// @param newValue_ The new bps value to set
    function updateReinvestRewardBps(AaveV3ERC4626ReinvestIncentive vault_, uint256 newValue_) external {
        if (msg.sender != manager) revert INVALID_ACCESS();
        if(newValue_ > 150) revert REINVEST_BPS_TOO_HIGH();
        emit UpdateReinvestRewardBps(vault_, newValue_);
        vault_.updateReinvestRewardBps(newValue_);
    }

    /// @notice Harvest rewards from specified vault
    /// @param vault_ The vault to harvest rewards from
    /// @param minAmountOut_ The minimum amount of asset to receive
    function harvestFrom(AaveV3ERC4626ReinvestIncentive vault_, uint256 minAmountOut_) external {
        vault_.harvest(minAmountOut_);
        emit HarvestERC4626Reinvest(vault_);
    }
}
