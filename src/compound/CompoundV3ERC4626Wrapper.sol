// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {CometMainInterface} from "./compound/IComet.sol";
import {LibCompound} from "./compound/LibCompound.sol";
import {ICometRewards} from "./compound/ICometRewards.sol";

import {DexSwap} from "./utils/swapUtils.sol";

/// @title CompoundV3StrategyWrapper - Custom implementation of yield-daddy wrappers with flexible reinvesting logic
/// Rationale: Forked protocols often implement custom functions and modules on top of forked code.
/// Example: Staking systems. Very common in DeFi. Re-investing/Re-Staking rewards on the Vault level can be included in permissionless way.
contract CompoundV3ERC4626Wrapper is ERC4626 {
    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using LibCompound for CometMainInterface;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Thrown when reinvest amount is not enough.
    error NotEnoughReinvestAmount_Error();

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint256 internal constant NO_ERROR = 0;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice Access Control for harvest() route
    address public immutable manager;

    /// @notice The Compound cToken contract
    CometMainInterface public immutable cToken;

    /// @notice The Compound rewards manager contract
    ICometRewards public immutable rewardsManager;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        ERC20 asset_, // underlying
        CometMainInterface cToken_, // compound concept of a share
        ICometRewards rewardsManager_,
        address manager_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        cToken = cToken_;
        rewardsManager = rewardsManager_;
        manager = manager_;
    }

    /// -----------------------------------------------------------------------
    /// Compound liquidity mining
    /// -----------------------------------------------------------------------


    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// We can't inherit directly from Yield-daddy because of rewardClaim lock
    /// -----------------------------------------------------------------------

    function totalAssets() public view virtual override returns (uint256) {
        return cToken.balanceOf(address(this));
    }
    
    function beforeWithdraw(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Withdraw assets from Compound
        /// -----------------------------------------------------------------------

        cToken.withdraw(address(asset), assets);
    }

    function afterDeposit(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Deposit assets into Compound
        /// -----------------------------------------------------------------------

        // approve to cToken
        asset.safeApprove(address(cToken), assets);

        // deposit into cToken
        cToken.supply(address(asset), assets);
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (cToken.isSupplyPaused()) return 0;
        return type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        if (cToken.isSupplyPaused()) return 0;
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        // uint256 cash = cToken.getCash();
        if (cToken.isWithdrawPaused()) return 0;
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        return assetsBalance;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        // uint256 cash = cToken.getCash();
        // uint256 cashInShares = convertToShares(cash);
        if (cToken.isWithdrawPaused()) return 0;
        uint256 shareBalance = balanceOf[owner];
        return shareBalance;
    }

    /// -----------------------------------------------------------------------
    /// ERC20 metadata generation
    /// -----------------------------------------------------------------------

    function _vaultName(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultName)
    {
        vaultName = string.concat("CompStratERC4626- ", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultSymbol)
    {
        vaultSymbol = string.concat("cS-", asset_.symbol());
    }
}
