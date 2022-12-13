// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {AaveV2ERC4626Reinvest} from "./AaveV2ERC4626Reinvest.sol";
import {IAaveMining} from "./aave/IAaveMining.sol";
import {ILendingPool} from "./aave/ILendingPool.sol";

/// @title AaveV2ERC4626Factory forked from @author zefram.eth
/// @notice Factory for creating AaveV2ERC4626 contracts
contract AaveV2ERC4626ReinvestFactory {

    /// @notice Emitted when a new ERC4626 vault has been created
    /// @param asset The base asset used by the vault
    /// @param vault The vault that was created
    event CreateERC4626Reinvest(ERC20 indexed asset, ERC4626 vault);

    /// @notice Emitted when swap routes have been set for a given aToken vault
    event RoutesSetERC4626Reinvest(AaveV2ERC4626Reinvest vault);

    /// @notice Emitted when harvest has been called for a given aToken vault
    event HarvestERC4626Reinvest(AaveV2ERC4626Reinvest vault);

    /// @notice Emitted when minTokensToReinvest has been updated for a given aToken vault
    event UpdateMinTokensToReinvest(AaveV2ERC4626Reinvest vault, uint256 minTokensToHarvest);

    /// @notice Emitted when reinvestRewardBps has been updated for a given aToken vault
    event UpdateReinvestRewardBps(AaveV2ERC4626Reinvest vault, uint256 reinvestRewardBps);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Thrown when trying to deploy an AaveV2ERC4626 vault using an asset without an aToken
    error AaveV2ERC4626Factory__ATokenNonexistent();

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The Aave liquidity mining contract
    IAaveMining public immutable aaveMining;

    /// @notice The Aave LendingPool contract
    ILendingPool public immutable lendingPool;

    /// @notice Manager for setting swap routes for harvest() per each vault
    address public immutable manager;

    /// @notice address of reward token from AAVE liquidity mining
    address public rewardToken;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        IAaveMining aaveMining_,
        ILendingPool lendingPool_,
        address rewardToken_,
        address manager_
    ) {
        /// @dev manager is only used for setting swap routes
        manager = manager_;

        /// @dev in case any of those contracts changes, we need to redeploy factory
        aaveMining = aaveMining_;
        lendingPool = lendingPool_;
        rewardToken = rewardToken_;

    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    function createERC4626(ERC20 asset)
        external
        virtual
        returns (ERC4626 vault)
    {
        require(msg.sender == manager, "onlyOwner");
        ILendingPool.ReserveData memory reserveData = lendingPool
            .getReserveData(address(asset));
        address aTokenAddress = reserveData.aTokenAddress;
        if (aTokenAddress == address(0)) {
            revert AaveV2ERC4626Factory__ATokenNonexistent();
        }

        vault = new AaveV2ERC4626Reinvest{salt: bytes32(0)}(
            asset,
            ERC20(aTokenAddress),
            aaveMining,
            lendingPool,
            rewardToken,
            address(this)
        );

        emit CreateERC4626Reinvest(asset, vault);
    }

    /// @notice Set swap routes for selling rewards
    /// @dev Centralizes setRoute on all createERC4626 deployments
    function setRoute(
        AaveV2ERC4626Reinvest vault_,
        address token,
        address pair1,
        address pair2
    ) external {
        require(msg.sender == manager, "onlyOwner");
        vault_.setRoute(token, pair1, pair2);

        emit RoutesSetERC4626Reinvest(vault_);
    }

    /**
     * @notice Update reinvest min threshold
     * @param newValue threshold
     */
    function updateMinTokensToReinvest(AaveV2ERC4626Reinvest vault_, uint256 newValue) external {
        require(msg.sender == manager, "onlyOwner");
        emit UpdateMinTokensToReinvest(vault_, newValue);
        vault_.updateMinTokensToHarvest(newValue);
    }

    /**
     * @notice Update reinvest min threshold
     * @param newValue threshold
     */
    function updateReinvestRewardBps(AaveV2ERC4626Reinvest vault_, uint256 newValue) external {
        require(msg.sender == manager, "onlyOwner");
        require(newValue <= 150, "reward too high");
        emit UpdateReinvestRewardBps(vault_, newValue);
        vault_.updateReinvestRewardBps(newValue);
    }

    /// @notice Harvest rewards from specified vault
    function harvestFrom(AaveV2ERC4626Reinvest vault_, uint256 minAmountOut_) external {
        vault_.harvest(minAmountOut_);
        emit HarvestERC4626Reinvest(vault_);
    }

}
