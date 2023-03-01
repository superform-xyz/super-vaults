// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IMultiFeeDistribution} from "./external/IMultiFeeDistribution.sol";
import {ILendingPool} from "./external/ILendingPool.sol";
import {DexSwap} from "./utils/swapUtils.sol";

/// @title GeistERC4626Reinvest - AAVE-V2 Forked protocol with Curve-like rewards distribution in place of IAaveMining.
/// NOTE: Base implementation contract with harvest() disabled as it would require vesting vault's balance.
contract GeistERC4626Reinvest is ERC4626 {
    address public immutable manager;

    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint256 internal constant ACTIVE_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFF;
    uint256 internal constant FROZEN_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFFFFFFFFFFFFFF;

    address public immutable spookySwap =
        0xF491e7B69E4244ad4002BC14e878a34207E38c29;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The Aave aToken contract
    ERC20 public immutable aToken;

    /// @notice The Aave liquidity mining contract
    IMultiFeeDistribution public immutable rewards;

    /// @notice GEIST token (reward)
    ERC20 public immutable rewardToken;

    /// @notice The Aave LendingPool contract
    ILendingPool public immutable lendingPool;

    /// @notice Pointer to swapInfo
    swapInfo public SwapInfo;

    /// Compact struct to make two swaps (SpookySwap on FTM)
    /// A => B (using pair1) then B => asset (of BaseWrapper) (using pair2)
    struct swapInfo {
        address token;
        address pair1;
        address pair2;
    }

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error MIN_AMOUNT_ERROR();

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        ERC20 asset_,
        ERC20 aToken_,
        IMultiFeeDistribution rewards_,
        ILendingPool lendingPool_,
        ERC20 rewardToken_,
        address manager_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        aToken = aToken_;
        rewards = rewards_;
        lendingPool = lendingPool_;
        rewardToken = rewardToken_;
        manager = manager_;
    }

    /// -----------------------------------------------------------------------
    /// Geist Rewards Module
    /// -----------------------------------------------------------------------

    function setRoute(
        address token,
        address pair1,
        address pair2
    ) external {
        require(msg.sender == manager, "onlyOwner");
        SwapInfo = swapInfo(token, pair1, pair2);
    }

    /// @notice Base implementation harvest() is non-operational as Vault is not vesting LP-token in Geist Reward Pool
    function harvest(uint256 minAmountOut_) external {
        
        /// Claim only without Penalty
        rewards.getReward();
        rewards.exit();

        uint256 earned = rewardToken.balanceOf(address(this));
        uint256 reinvestAmount;

        if (SwapInfo.token == address(asset)) {
            rewardToken.approve(SwapInfo.pair1, earned);

            reinvestAmount = DexSwap.swap(
                earned,
                address(rewardToken), // from GEIST
                SwapInfo.token, /// to intermediary token FTM (no direct pools)
                SwapInfo.pair1 /// pairToken (pool)
            );
        } else {

            rewardToken.approve(SwapInfo.pair1, earned);

            /// Swap on Spooky
            uint256 swapTokenAmount = DexSwap.swap(
                earned,
                address(rewardToken), // from GEIST
                SwapInfo.token, /// to intermediary token FTM (no direct pools)
                SwapInfo.pair1 /// pairToken (pool)
            );

            ERC20(SwapInfo.token).approve(SwapInfo.pair2, swapTokenAmount);

            reinvestAmount = DexSwap.swap(
                swapTokenAmount,
                SwapInfo.token, // from received FTM
                address(asset), /// to target underlying of BaseWrapper Vault
                SwapInfo.pair2 /// pairToken (pool)
            );
        }
        if(reinvestAmount < minAmountOut_) {
            revert MIN_AMOUNT_ERROR();
        }
        afterDeposit(asset.balanceOf(address(this)), 0);
    }

    function getRewardsAccrued() public view returns (IMultiFeeDistribution.RewardData[] memory r) {
        return rewards.claimableRewards(address(this));
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        // withdraw assets directly from Aave
        lendingPool.withdraw(address(asset), assets, receiver);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        // withdraw assets directly from Aave
        lendingPool.withdraw(address(asset), assets, receiver);
    }

    function totalAssets() public view virtual override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function afterDeposit(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Deposit assets into Aave
        /// -----------------------------------------------------------------------

        // approve to lendingPool
        asset.safeApprove(address(lendingPool), assets);

        // deposit into lendingPool
        lendingPool.deposit(address(asset), assets, address(this), 0);
    }

    function maxDeposit(address)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // check if pool is paused
        if (lendingPool.paused()) {
            return 0;
        }

        // check if asset is paused
        uint256 configData = lendingPool
            .getReserveData(address(asset))
            .configuration
            .data;
        if (!(_getActive(configData) && !_getFrozen(configData))) {
            return 0;
        }

        return type(uint256).max;
    }

    function maxMint(address) public view virtual override returns (uint256) {
        // check if pool is paused
        if (lendingPool.paused()) {
            return 0;
        }

        // check if asset is paused
        uint256 configData = lendingPool
            .getReserveData(address(asset))
            .configuration
            .data;
        if (!(_getActive(configData) && !_getFrozen(configData))) {
            return 0;
        }

        return type(uint256).max;
    }

    function maxWithdraw(address owner)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // check if pool is paused
        if (lendingPool.paused()) {
            return 0;
        }

        // check if asset is paused
        uint256 configData = lendingPool
            .getReserveData(address(asset))
            .configuration
            .data;
        if (!_getActive(configData)) {
            return 0;
        }

        uint256 cash = asset.balanceOf(address(aToken));
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    function maxRedeem(address owner)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // check if pool is paused
        if (lendingPool.paused()) {
            return 0;
        }

        // check if asset is paused
        uint256 configData = lendingPool
            .getReserveData(address(asset))
            .configuration
            .data;
        if (!_getActive(configData)) {
            return 0;
        }

        uint256 cash = asset.balanceOf(address(aToken));
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
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
        vaultName = string.concat("ERC4626-Wrapped Geist-", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultSymbol)
    {
        vaultSymbol = string.concat("gs4626-", asset_.symbol());
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _getActive(uint256 configData) internal pure returns (bool) {
        return configData & ~ACTIVE_MASK != 0;
    }

    function _getFrozen(uint256 configData) internal pure returns (bool) {
        return configData & ~FROZEN_MASK != 0;
    }
}
