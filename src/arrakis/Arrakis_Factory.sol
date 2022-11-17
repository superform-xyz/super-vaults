// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ArrakisNonNativeVault, IArrakisRouter, IGUniPool} from "./Arrakis_Non_Native_LP_Vault.sol";

interface IStakePool {
    function staking_token() external view returns (address);
}

/// @title ArrakisFactory
/// @author diszsid.eth
/// @notice Factory for creating ArrakisERC4626 contracts
contract ArrakisFactory {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Thrown when trying to deploy an Arrakis vault using an asset with an invalid Arrakis pool
    error ArrakisFactory__UniPoolInvalid();

   /// @notice Thrown when trying to deploy an Arrakis vault using an asset with an invalid staking gauge pool
    error ArrakisFactory__GaugeInvalid();

   /// @notice Thrown when trying to deploy an Arrakis factory using an invalid arrakis router
    error ArrakisFactory__routerInvalid();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    /// @notice Emitted when a new ERC4626 vault has been created
    /// @param gUniPool The base pool used to create the vaults
    /// @param vaultA The vault that was created with token0 as asset
    /// @param vaultB The vault that was created with token1 as asset
    event ArrakisVaultsCreated(address indexed gUniPool, ArrakisNonNativeVault vaultA, ArrakisNonNativeVault vaultB);

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The Arrakis Router contract
    IArrakisRouter public immutable arrakisRouter;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        address _arrakisRouter
    ) {
        if(address(_arrakisRouter) == address(0))
            revert ArrakisFactory__routerInvalid();
        arrakisRouter = IArrakisRouter(_arrakisRouter);
    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    function createArrakisVaults(
        address _gUniPool,
        string memory _name,
        string memory _symbol,
        address _gauge,
        uint160 _slippage
    ) external returns(ArrakisNonNativeVault vaultA, ArrakisNonNativeVault vaultB) {
        IGUniPool pool = IGUniPool(_gUniPool);
        ERC20 token0 = pool.token0();
        ERC20 token1 = pool.token1();
        if(address(token0) == address(0) || address(token1) == address(0) || address(token0) == address(token1) )
            revert ArrakisFactory__UniPoolInvalid();
        if(address(_gauge) == address(0) || IStakePool(_gauge).staking_token() != address(_gUniPool))
            revert ArrakisFactory__GaugeInvalid();
        vaultA = new ArrakisNonNativeVault{salt: bytes32(0)}(_gUniPool, _name, _symbol, true, address(arrakisRouter), _gauge, _slippage);
        vaultB = new ArrakisNonNativeVault{salt: bytes32(0)}(_gUniPool, _name, _symbol, false, address(arrakisRouter), _gauge, _slippage);
        emit ArrakisVaultsCreated(_gUniPool, vaultA, vaultB);
    }
}