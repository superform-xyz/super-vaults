// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {IPool} from "./external/IPool.sol";
import {AaveV3ERC4626Reinvest} from "./AaveV3ERC4626Reinvest.sol";
import {IRewardsController} from "./external/IRewardsController.sol";

/// @title AaveV3ERC4626Factory forked from @author zefram.eth
/// @notice Factory for creating AaveV2ERC4626 contracts
contract AaveV3ERC4626ReinvestFactory {

    address public manager;

    /// @notice Emitted when a new ERC4626 vault has been created
    /// @param asset The base asset used by the vault
    /// @param vault The vault that was created
    event CreateERC4626Reinvest(ERC20 indexed asset, ERC4626 vault);

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

    constructor(IPool lendingPool_, IRewardsController rewardsController_, address manager_) {
        lendingPool = lendingPool_;
        rewardsController = rewardsController_;

        /// @dev manager is only used for setting swap routes
        /// TODO: Redesign it / limit AC more
        manager = manager_;
    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    function createERC4626(ERC20 asset) external virtual returns (ERC4626 vault) {
        IPool.ReserveData memory reserveData = lendingPool.getReserveData(address(asset));
        address aTokenAddress = reserveData.aTokenAddress;
        if (aTokenAddress == address(0)) {
            revert AaveV3ERC4626Factory__ATokenNonexistent();
        }

        vault =
        new AaveV3ERC4626Reinvest{salt: bytes32(0)}(asset, ERC20(aTokenAddress), lendingPool, rewardsController, manager);

        emit CreateERC4626Reinvest(asset, vault);
    }

}
