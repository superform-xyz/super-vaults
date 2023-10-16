// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {AaveV2ERC4626ReinvestIncentive} from "./AaveV2ERC4626ReinvestIncentive.sol";
import {IAaveMining} from "./aave/IAaveMining.sol";
import {ILendingPool} from "./aave/ILendingPool.sol";

/// @title AaveV2ERC4626ReinvestFactory
/// @notice Factory for creating AaveV2ERC4626Reinvest contracts
/// @notice Forked from yield daddy Aave-V2-ERC4626-Factory wrapper
/// @author ZeroPoint Labs
contract AaveV2ERC4626ReinvestIncentiveFactory {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new ERC4626 vault has been created
    /// @param asset The base asset used by the vault
    /// @param vault The vault that was created
    event CreateERC4626Reinvest(ERC20 indexed asset, ERC4626 vault);

    /// @notice Emitted when swap routes have been set for a given aToken vault
    event RoutesSetERC4626Reinvest(AaveV2ERC4626ReinvestIncentive vault);

    /// @notice Emitted when harvest has been called for a given aToken vault
    event HarvestERC4626Reinvest(AaveV2ERC4626ReinvestIncentive vault);

    /// @notice Emitted when minTokensToReinvest has been updated for a given aToken vault
    event UpdateMinTokensToReinvest(AaveV2ERC4626ReinvestIncentive vault, uint256 minTokensToHarvest);

    /// @notice Emitted when reinvestRewardBps has been updated for a given aToken vault
    event UpdateReinvestRewardBps(AaveV2ERC4626ReinvestIncentive vault, uint256 reinvestRewardBps);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to deploy an AaveV2ERC4626 vault using an asset without an aToken
    error ATOKEN_NON_EXISTENT();

    /// @notice Thrown when trying to call a function that is restricted
    error INVALID_ACCESS();

    /// @notice Thrown when amount for reinvest reward bps is too high
    error REWARD_TOO_HIGH();

    /*//////////////////////////////////////////////////////////////
                      IMMUTABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The Aave liquidity mining contract
    IAaveMining public immutable aaveMining;

    /// @notice The Aave LendingPool contract
    ILendingPool public immutable lendingPool;

    /// @notice Manager for setting swap routes for harvest() per each vault
    address public immutable manager;

    /// @notice address of reward token from AAVE liquidity mining
    address public rewardToken;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Construct a new AaveV2ERC4626Factory
    /// @param aaveMining_ The Aave liquidity mining contract
    /// @param lendingPool_ The Aave LendingPool contract
    /// @param rewardToken_ address of reward token from AAVE liquidity mining
    /// @param manager_ Manager for setting swap routes for harvest() per each vault
    constructor(IAaveMining aaveMining_, ILendingPool lendingPool_, address rewardToken_, address manager_) {
        manager = manager_;

        /// @dev in case any of those contracts changes, we need to redeploy factory
        aaveMining = aaveMining_;
        lendingPool = lendingPool_;
        rewardToken = rewardToken_;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new AaveV2ERC4626 vault
    /// @param asset_ The base asset used by the vault
    function createERC4626(ERC20 asset_) external virtual returns (ERC4626 vault) {
        if (msg.sender != manager) revert INVALID_ACCESS();
        ILendingPool.ReserveData memory reserveData = lendingPool.getReserveData(address(asset_));
        address aTokenAddress = reserveData.aTokenAddress;
        if (aTokenAddress == address(0)) {
            revert ATOKEN_NON_EXISTENT();
        }

        vault = new AaveV2ERC4626ReinvestIncentive{salt: bytes32(0)}(
            asset_,
            ERC20(aTokenAddress),
            aaveMining,
            lendingPool,
            rewardToken,
            address(this)
        );

        emit CreateERC4626Reinvest(asset_, vault);
    }

    /// @notice Set swap routes for selling rewards
    /// @dev Centralizes setRoute on all createERC4626 deployments
    /// @param vault_ The vault to set routes on
    /// @param token_ The token to swap for
    /// @param pair1_ The address of the pool pair containing harvested token/middle token
    /// @param pair2_ The address of the pool pair containing middle token/base token
    function setRoute(AaveV2ERC4626ReinvestIncentive vault_, address token_, address pair1_, address pair2_) external {
        if (msg.sender != manager) revert INVALID_ACCESS();
        vault_.setRoute(token_, pair1_, pair2_);

        emit RoutesSetERC4626Reinvest(vault_);
    }

    /**
     * @notice Update reinvest min threshold
     * @param newValue_ threshold
     */
    function updateMinTokensToReinvest(AaveV2ERC4626ReinvestIncentive vault_, uint256 newValue_) external {
        if (msg.sender != manager) revert INVALID_ACCESS();
        emit UpdateMinTokensToReinvest(vault_, newValue_);
        vault_.updateMinTokensToHarvest(newValue_);
    }

    /**
     * @notice Update reinvest min threshold
     * @param newValue_ threshold
     */
    function updateReinvestRewardBps(AaveV2ERC4626ReinvestIncentive vault_, uint256 newValue_) external {
        if (msg.sender != manager) revert INVALID_ACCESS();
        if (newValue_ > 150) revert REWARD_TOO_HIGH();
        emit UpdateReinvestRewardBps(vault_, newValue_);
        vault_.updateReinvestRewardBps(newValue_);
    }

    /// @notice Harvest rewards from specified vault
    /// @param minAmountOut_ Minimum amount of asset to reinvest
    function harvestFrom(AaveV2ERC4626ReinvestIncentive vault_, uint256 minAmountOut_) external {
        vault_.harvest(minAmountOut_);
        emit HarvestERC4626Reinvest(vault_);
    }
}
