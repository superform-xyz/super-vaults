// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ArrakisNonNativeVault, IArrakisRouter, IGUniPool} from "./Arrakis_Non_Native_LP_Vault.sol";

interface IStakePool {
    function staking_token() external view returns (address);
}

/// @title ArrakisFactory
/// @notice Factory for creating ArrakisERC4626 contracts
/// @author ZeroPoint Labs
contract ArrakisFactory {
    /*//////////////////////////////////////////////////////////////
                      ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to deploy an Arrakis vault using an asset with an invalid Arrakis pool
    error ArrakisFactory__UniPoolInvalid();

   /// @notice Thrown when trying to deploy an Arrakis vault using an asset with an invalid staking gauge pool
    error ArrakisFactory__GaugeInvalid();

   /// @notice Thrown when trying to deploy an Arrakis factory using an invalid arrakis router
    error ArrakisFactory__routerInvalid();

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
    constructor(
        address arrakisRouter_
    ) {
        if(address(arrakisRouter_) == address(0))
            revert ArrakisFactory__routerInvalid();
        arrakisRouter = IArrakisRouter(arrakisRouter_);
    }

    /*//////////////////////////////////////////////////////////////
                      EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function createArrakisVaults(
        address gUniPool_,
        string memory name_,
        string memory symbol_,
        address gauge_,
        uint160 slippage_
    ) external returns(ArrakisNonNativeVault vaultA, ArrakisNonNativeVault vaultB) {
        IGUniPool pool = IGUniPool(gUniPool_);
        ERC20 token0 = pool.token0();
        ERC20 token1 = pool.token1();
        if(address(token0) == address(0) || address(token1) == address(0) || address(token0) == address(token1) )
            revert ArrakisFactory__UniPoolInvalid();
        if(address(gauge_) == address(0) || IStakePool(gauge_).staking_token() != address(gUniPool_))
            revert ArrakisFactory__GaugeInvalid();
        vaultA = new ArrakisNonNativeVault{salt: bytes32(0)}(gUniPool_, name_, symbol_, true, address(arrakisRouter), gauge_, slippage_);
        vaultB = new ArrakisNonNativeVault{salt: bytes32(0)}(gUniPool_, name_, symbol_, false, address(arrakisRouter), gauge_, slippage_);
        emit ArrakisVaultsCreated(gUniPool_, vaultA, vaultB);
    }
}