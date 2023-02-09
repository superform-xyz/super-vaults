// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {ILendingPool} from "./aave/ILendingPool.sol";
import {IAaveMining} from "./aave/IAaveMining.sol";

import {DexSwap} from "./utils/swapUtils.sol";

/// @title AaveV2ERC4626Reinvest - extended implementation of yield-daddy @author zefram.eth
/// @dev Reinvests rewards accrued for higher APY
contract AaveV2ERC4626Reinvest is ERC4626 {
    
    address public immutable manager;
    address public rewardToken;
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

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

        // @notice Thrown when reinvested amounts are not enough.
    error MIN_AMOUNT_ERROR();

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The Aave aToken contract (rebasing)
    ERC20 public immutable aToken;

    /// @notice The Aave-fork liquidity mining contract (implementations can differ)
    IAaveMining public immutable rewards;

    /// @notice Check if rewards have been set before harvest() and setRoutes()
    bool public rewardsSet;

    /// @notice The Aave LendingPool contract
    ILendingPool public immutable lendingPool;

    /// @notice Pointer to swapInfo
    swapInfo public SwapInfo;

    /// Compact struct to make two swaps (on Uniswap v2)
    /// A => B (using pair1) then B => asset (of Wrapper) (using pair2)
    struct swapInfo {
        address token;
        address pair1;
        address pair2;
    }

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        ERC20 asset_,
        ERC20 aToken_,
        IAaveMining rewards_,
        ILendingPool lendingPool_,
        address rewardToken_,
        address manager_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        aToken = aToken_;
        rewards = rewards_;
        lendingPool = lendingPool_;
        rewardToken = rewardToken_;
        manager = manager_;

        /// TODO: tighter checks
        rewardsSet = false;
    }

    /// -----------------------------------------------------------------------
    /// AAVE-Fork Rewards Module
    /// -----------------------------------------------------------------------
    
    /// @notice Set swap routes for selling rewards
    /// @dev Setting wrong addresses here will revert harvest() calls
    function setRoute(
        address token,
        address pair1,
        address pair2
    ) external {
        require(msg.sender == manager, "onlyOwner");
        SwapInfo = swapInfo(token, pair1, pair2);
        rewardsSet = true;
    }

    /// @notice Claims liquidity providing rewards from AAVE-Fork and performs low-lvl swap with instant reinvesting
    function harvest(uint256 minAmountOut_) external {

        /// @dev Claim rewards from AAVE-Fork
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        uint256 earned = rewards.claimRewards(assets, type(uint256).max, address(this));
        
        ERC20 rewardToken_ = ERC20(rewardToken);
        uint256 reinvestAmount;

        /// If one swap needed (high liquidity pair) - set swapInfo.token0/token/pair2 to 0x
        /// @dev Swap AAVE-Fork token for asset
        if (SwapInfo.token == address(asset)) {

            rewardToken_.approve(SwapInfo.pair1, earned); /// max approves address

            reinvestAmount = DexSwap.swap(
                earned, /// REWARDS amount to swap
                rewardToken, // from REWARD-TOKEN
                address(asset), /// to target underlying of this Vault
                SwapInfo.pair1 /// pairToken (pool)
            );
        /// If two swaps needed
        } else {

            rewardToken_.approve(SwapInfo.pair1, type(uint256).max); /// max approves address

            uint256 swapTokenAmount = DexSwap.swap(
                earned,
                rewardToken, // from AAVE-Fork
                SwapInfo.token, /// to intermediary token with high liquidity (no direct pools)
                SwapInfo.pair1 /// pairToken (pool)
            );

            ERC20(SwapInfo.token).approve(SwapInfo.pair2, swapTokenAmount); 

            reinvestAmount = DexSwap.swap(
                swapTokenAmount,
                SwapInfo.token, // from received token
                address(asset), /// to target underlying of this Vault
                SwapInfo.pair2 /// pairToken (pool)
            );
        }
        if(reinvestAmount < minAmountOut_) {
            revert MIN_AMOUNT_ERROR();
        }
        /// reinvest() without minting (no asset.totalSupply() increase == profit)
        afterDeposit(asset.balanceOf(address(this)), 0);
    }
    
    /// @notice Check how much rewards are available to claim, useful before harvest()
    function getRewardsAccrued() external view returns (uint256) {
        return rewards.getUserUnclaimedRewards(address(this));
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
        // aTokens use rebasing to accrue interest, so the total assets is just the aToken balance
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
        vaultName = string.concat("ERC4626-Wrapped Aave v2 ", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultSymbol)
    {
        vaultSymbol = string.concat("wa2-", asset_.symbol());
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