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

    /// @notice DAO owner
    address public immutable manager;

    /// @notice address of reward token from AAVE liquidity mining
    /// TODO: Setter for this
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
        /// TODO: Redesign it / limit AC more
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
            manager
        );

        emit CreateERC4626Reinvest(asset, vault);
    }

}
