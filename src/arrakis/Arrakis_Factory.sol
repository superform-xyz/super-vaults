// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ArrakisNonNativeVault, IArrakisRouter, IGUniPool} from "./Arrakis_Non_Native_LP_Vault.sol";
import {IStakePool} from "./interfaces/IStakePool.sol";

/// @title ArrakisFactory
/// @notice Factory for creating ArrakisERC4626 contracts
/// @author ZeroPoint Labs
contract ArrakisFactory {
    /*//////////////////////////////////////////////////////////////
                      ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to deploy an Arrakis vault using an asset with an invalid Arrakis pool
    error UNI_POOL_INVALID();

    /// @notice Thrown when trying to deploy an Arrakis vault using an asset with an invalid staking gauge pool
    error GAUGE_INVALID();

    /// @notice Thrown when trying to deploy an Arrakis factory using an invalid arrakis router
    error ROUTER_INVALID();

    /*//////////////////////////////////////////////////////////////
                      EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new ERC4626 vault has been created
    /// @param gUniPool The base pool used to create the vaults
    /// @param vaultA The vault that was created with token0 as asset
    /// @param vaultB The vault that was created with token1 as asset
    event ArrakisVaultsCreated(address indexed gUniPool, ArrakisNonNativeVault vaultA, ArrakisNonNativeVault vaultB);

    /*//////////////////////////////////////////////////////////////
                      IMMUTABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The Arrakis Router contract
    IArrakisRouter public immutable arrakisRouter;

    /*//////////////////////////////////////////////////////////////
                      CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Construct a new ArrakisFactory contract
    /// @param arrakisRouter_ The Arrakis Router contract
    constructor(address arrakisRouter_) {
        if (address(arrakisRouter_) == address(0)) revert ROUTER_INVALID();
        arrakisRouter = IArrakisRouter(arrakisRouter_);
    }

    /*//////////////////////////////////////////////////////////////
                      EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new Arrakis vault
    /// @param gUniPool_ The Arrakis pool to use
    /// @param name_ The name of the vault
    /// @param symbol_ The symbol of the vault
    /// @param gauge_ The staking gauge pool
    /// @param slippage_ The slippage tolerance for swaps
    function createArrakisVaults(
        address gUniPool_,
        string memory name_,
        string memory symbol_,
        address gauge_,
        uint160 slippage_
    ) external returns (ArrakisNonNativeVault vaultA, ArrakisNonNativeVault vaultB) {
        IGUniPool pool = IGUniPool(gUniPool_);
        ERC20 token0 = pool.token0();
        ERC20 token1 = pool.token1();
        if (address(token0) == address(0) || address(token1) == address(0) || address(token0) == address(token1)) {
            revert UNI_POOL_INVALID();
        }
        if (address(gauge_) == address(0) || IStakePool(gauge_).staking_token() != address(gUniPool_)) {
            revert GAUGE_INVALID();
        }
        vaultA = new ArrakisNonNativeVault{salt: bytes32(0)}(
            gUniPool_,
            name_,
            symbol_,
            true,
            address(arrakisRouter),
            gauge_,
            slippage_
        );
        vaultB = new ArrakisNonNativeVault{salt: bytes32(0)}(
            gUniPool_,
            name_,
            symbol_,
            false,
            address(arrakisRouter),
            gauge_,
            slippage_
        );
        emit ArrakisVaultsCreated(gUniPool_, vaultA, vaultB);
    }
}
