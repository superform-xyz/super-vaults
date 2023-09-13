// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {IPool} from "./external/IPool.sol";
import {AaveV3ERC4626Reinvest} from "./AaveV3ERC4626Reinvest.sol";
import {IRewardsController} from "./external/IRewardsController.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

/// @title AaveV3ERC4626ReinvestFactory
/// @notice Factory for creating AaveV3ERC4626 contracts
/// @notice Forked from zefram.eth
/// @author ZeroPoint Labs
contract AaveV3ERC4626ReinvestFactory {
    /*//////////////////////////////////////////////////////////////
                      LIBRARIES USAGE
    //////////////////////////////////////////////////////////////*/
    using Bytes32AddressLib for bytes32;

    /*//////////////////////////////////////////////////////////////
                      EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new ERC4626 vault has been created
    /// @param asset The base asset used by the vault
    /// @param vault The vault that was created
    event CreateERC4626Reinvest(ERC20 indexed asset, AaveV3ERC4626Reinvest vault);

    /// @notice Emitted when rewards for a given aToken vault have been set
    event RewardsSetERC4626Reinvest(AaveV3ERC4626Reinvest vault);

    /// @notice Emitted when swap routes have been set for a given aToken vault
    event RoutesSetERC4626Reinvest(AaveV3ERC4626Reinvest vault);

    /// @notice Emitted when harvest has been called for a given aToken vault
    event HarvestERC4626Reinvest(AaveV3ERC4626Reinvest vault);

    /*//////////////////////////////////////////////////////////////
                      ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to deploy an AaveV3ERC4626 vault using an asset without an aToken
    error ATOKEN_NON_EXISTENT();
    /// @notice Thrown when trying to call a permissioned function with an invalid access
    error INVALID_ACCESS();

    /*//////////////////////////////////////////////////////////////
                      IMMUTABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The Aave Pool contract
    IPool public immutable lendingPool;

    /// @notice The Aave RewardsController contract
    IRewardsController public immutable rewardsController;

    /// @notice Manager for setting swap routes for harvest() per each vault
    address public manager;

    /// @notice Mapping of vaults by asset
    mapping(address => AaveV3ERC4626Reinvest) public vaults;

    /*//////////////////////////////////////////////////////////////
                      CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructs the AaveV3ERC4626Factory
    /// @param lendingPool_ The Aave Pool contract
    /// @param rewardsController_ The Aave RewardsController contract
    /// @param manager_ The manager for setting swap routes
    constructor(IPool lendingPool_, IRewardsController rewardsController_, address manager_) {
        lendingPool = lendingPool_;
        rewardsController = rewardsController_;

        /// @dev manager is only used for setting swap routes
        manager = manager_;
    }

    /*//////////////////////////////////////////////////////////////
                      EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function createERC4626(ERC20 asset_) external virtual returns (AaveV3ERC4626Reinvest vault) {
        if (msg.sender != manager) revert INVALID_ACCESS();
        IPool.ReserveData memory reserveData = lendingPool.getReserveData(address(asset_));
        address aTokenAddress = reserveData.aTokenAddress;
        if (aTokenAddress == address(0)) {
            revert ATOKEN_NON_EXISTENT();
        }

        vault = new AaveV3ERC4626Reinvest(
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
    function setRewards(AaveV3ERC4626Reinvest vault_) external returns (address[] memory rewards) {
        if (msg.sender != manager) revert INVALID_ACCESS();
        rewards = vault_.setRewards();

        emit RewardsSetERC4626Reinvest(vault_);
    }

    /// @notice Set swap routes for selling rewards
    /// @dev Centralizes setRoutes on all createERC4626 deployments
    /// @param vault_ The vault to set routes for
    /// @param rewardToken_ The reward token address
    /// @param token_ The token to swap rewardToken_ to
    /// @param pair1_ The first pair to swap rewardToken_ to token_
    /// @param pair2_ The second pair to swap token_ to asset_
    function setRoutes(
        AaveV3ERC4626Reinvest vault_,
        address rewardToken_,
        address token_,
        address pair1_,
        address pair2_
    ) external {
        if (msg.sender != manager) revert INVALID_ACCESS();
        vault_.setRoutes(rewardToken_, token_, pair1_, pair2_);

        emit RoutesSetERC4626Reinvest(vault_);
    }

    /// @notice Harvest rewards from specified vault
    /// @param vault_ The vault to harvest from
    /// @param minAmountOuts_ The minimum amount of underlying asset token to receive for each reward token
    function harvestFrom(AaveV3ERC4626Reinvest vault_, uint256[] memory minAmountOuts_) external {
        vault_.harvest(minAmountOuts_);
        emit HarvestERC4626Reinvest(vault_);
    }
}
