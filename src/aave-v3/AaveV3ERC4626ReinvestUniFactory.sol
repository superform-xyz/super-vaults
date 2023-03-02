// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {IPool} from "./external/IPool.sol";
import {AaveV3ERC4626ReinvestUni} from "./AaveV3ERC4626ReinvestUni.sol";
import {IRewardsController} from "./external/IRewardsController.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

/// @title AaveV3ERC4626ReinvestUniFactory
/// @notice Forked from yield-daddy AaveV3ERC4626Factory for creating AaveV3ERC4626 contracts
/// @author ZeroPoint Labs
contract AaveV3ERC4626ReinvestUniFactory {
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
    mapping(address => AaveV3ERC4626ReinvestUni) public vaults;

    /*//////////////////////////////////////////////////////////////
                        EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new ERC4626 vault has been created
    /// @param asset The base asset used by the vault
    /// @param vault The vault that was created
    event CreateERC4626Reinvest(
        ERC20 indexed asset,
        AaveV3ERC4626ReinvestUni vault
    );

    /// @notice Emitted when rewards for a given aToken vault have been set
    event RewardsSetERC4626Reinvest(AaveV3ERC4626ReinvestUni vault);

    /// @notice Emitted when swap routes have been set for a given aToken vault
    event RoutesSetERC4626Reinvest(AaveV3ERC4626ReinvestUni vault);

    /// @notice Emitted when harvest has been called for a given aToken vault
    event HarvestERC4626Reinvest(AaveV3ERC4626ReinvestUni vault);

    /*//////////////////////////////////////////////////////////////
                      ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to deploy an AaveV3ERC4626 vault using an asset without an aToken
    error ATOKEN_NON_EXISTENT();

    /// @notice Thrown when trying to call a function with an invalid access
    error INVALID_ACCESS();

    /*//////////////////////////////////////////////////////////////
                      IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The Aave Pool contract
    IPool public immutable lendingPool;

    /// @notice The Aave RewardsController contract
    IRewardsController public immutable rewardsController;

    /*//////////////////////////////////////////////////////////////
                      CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Construct a new AaveV3ERC4626ReinvestUniFactory
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

    /// @notice Create a new AaveV3ERC4626ReinvestUni vault
    /// @param asset_ The base asset used by the vault
    function createERC4626(ERC20 asset_)
        external
        virtual
        returns (AaveV3ERC4626ReinvestUni vault)
    {
        if (msg.sender != manager) revert INVALID_ACCESS();
        IPool.ReserveData memory reserveData = lendingPool.getReserveData(
            address(asset_)
        );
        address aTokenAddress = reserveData.aTokenAddress;
        if (aTokenAddress == address(0)) {
            revert ATOKEN_NON_EXISTENT();
        }

        vault = new AaveV3ERC4626ReinvestUni(
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
    /// @param vault_ The vault to set rewards for
    function setRewards(AaveV3ERC4626ReinvestUni vault_)
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
    /// @param rewardToken_ The reward token to set route for
    /// @param poolFee1_ The fee for the first pool
    /// @param tokenMid_ The token to swap to before the second pool
    /// @param poolFee2_ The fee for the second pool
    function setRoutes(
        AaveV3ERC4626ReinvestUni vault_,
        address rewardToken_,
        uint24 poolFee1_,
        address tokenMid_,
        uint24 poolFee2_
    ) external {
        if (msg.sender != manager) revert INVALID_ACCESS();
        vault_.setRoutes(rewardToken_, poolFee1_, tokenMid_, poolFee2_);

        emit RoutesSetERC4626Reinvest(vault_);
    }

    /// @notice Harvest rewards from specified vault
    /// @param vault_ The vault to harvest from
    /// @param minAmountOuts_ The minimum amount of underlying asset to receive for each reward token we harvest from
    function harvestFrom(
        AaveV3ERC4626ReinvestUni vault_,
        uint256[] calldata minAmountOuts_
    ) external {
        vault_.harvest(minAmountOuts_);
        emit HarvestERC4626Reinvest(vault_);
    }
}
