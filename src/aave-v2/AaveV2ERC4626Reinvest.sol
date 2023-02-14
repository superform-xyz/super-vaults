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
    
    /*//////////////////////////////////////////////////////////////
                      LIBRARIES USED
    //////////////////////////////////////////////////////////////*/

    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                      CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant ACTIVE_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFF;
    uint256 internal constant FROZEN_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFFFFFFFFFFFFFF;

    /*//////////////////////////////////////////////////////////////
                      ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when reinvested amounts are not enough.
    error MIN_AMOUNT_ERROR();
    /// @notice Thrown when trying to call a function that is restricted
    error INVALID_ACCESS();
    /// @notice Thrown when trying to redeem shares worth 0 assets
    error ZERO_ASSETS();

    /*//////////////////////////////////////////////////////////////
                      IMMUTABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

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

    /// @notice Manager for setting swap routes for harvest() per each vault
    address public immutable manager;
    /// @notice address of reward token from AAVE liquidity mining
    address public rewardToken;

    /*//////////////////////////////////////////////////////////////
                      CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new AaveV2ERC4626Reinvest
    /// @param asset_ The underlying asset
    /// @param aToken_ The Aave aToken contract
    /// @param rewards_ The Aave-fork liquidity mining contract
    /// @param lendingPool_ The Aave LendingPool contract
    /// @param rewardToken_ The Aave-fork liquidity mining reward token
    /// @param manager_ The manager for setting swap routes for harvest() per each vault
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

    /*//////////////////////////////////////////////////////////////
                      AAVE-FORK REWARDS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Set swap routes for selling rewards
    /// @dev Setting wrong addresses here will revert harvest() calls
    /// @param token_ address of intermediary token with high liquidity (no direct pools)
    /// @param pair1_ address of pairToken (pool) for first swap (rewardToken => high liquidity token)
    /// @param pair2_ address of pairToken (pool) for second swap (high liquidity token => asset)
    function setRoute(
        address token_,
        address pair1_,
        address pair2_
    ) external {
        if(msg.sender != manager) revert INVALID_ACCESS();
        SwapInfo = swapInfo(token_, pair1_, pair2_);
        rewardsSet = true;
    }

    /// @notice Claims liquidity providing rewards from AAVE-Fork and performs low-lvl swap with instant reinvesting
    /// @param minAmountOut_ minimum amount of asset to receive after 2 swaps
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

    /*//////////////////////////////////////////////////////////////
                      ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    ///@notice Withdraws assets from Aave and burns shares
    ///@param assets_ Amount of assets to withdraw
    ///@param receiver_ Address to send withdrawn assets to
    ///@param owner_ Address to burn shares from
    function withdraw(
        uint256 assets_,
        address receiver_,
        address owner_
    ) public virtual override returns (uint256 shares) {
        shares = previewWithdraw(assets_); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets_, shares);

        _burn(owner_, shares);

        emit Withdraw(msg.sender, receiver_, owner_, assets_, shares);

        // withdraw assets directly from Aave
        lendingPool.withdraw(address(asset), assets_, receiver_);
    }

    ///@notice Redeems assets from Aave and burns shares
    ///@param shares_ Amount of shares to redeem
    ///@param receiver_ Address to send redeemed assets to
    ///@param owner_ Address to burn shares from
    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) public virtual override returns (uint256 assets) {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares_;
        }

        // Check for rounding error since we round down in previewRedeem.
        if((assets = previewRedeem(shares_)) == 0) {
            revert ZERO_ASSETS();
        }

        beforeWithdraw(assets, shares_);

        _burn(owner_, shares_);

        emit Withdraw(msg.sender, receiver_, owner_, assets, shares_);

        // withdraw assets directly from Aave
        lendingPool.withdraw(address(asset), assets, receiver_);
    }

    ///@notice returns total a tokens in the vault
    function totalAssets() public view virtual override returns (uint256) {
        // aTokens use rebasing to accrue interest, so the total assets is just the aToken balance
        return aToken.balanceOf(address(this));
    }

    ///@notice called by deposit and mint to deposit assets into Aave
    ///@param assets_ Amount of assets to deposit
    function afterDeposit(
        uint256 assets_,
        uint256 /*shares_*/
    ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Deposit assets into Aave
        /// -----------------------------------------------------------------------

        // approve to lendingPool
        asset.safeApprove(address(lendingPool), assets_);

        // deposit into lendingPool
        lendingPool.deposit(address(asset), assets_, address(this), 0);
    }

    ///@notice returns max amount of assets that can be deposited
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

    ///@notice returns max amount of assets that can be minted
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

    ///@notice returns max amount of assets that can be withdrawn
    ///@param owner_ Address to check max withdraw for
    function maxWithdraw(address owner_)
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
        uint256 assetsBalance = convertToAssets(balanceOf[owner_]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    ///@notice returns max amount of shares that can be redeemed
    ///@param owner_ Address to check max redeem for
    function maxRedeem(address owner_)
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
        uint256 shareBalance = balanceOf[owner_];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    /*//////////////////////////////////////////////////////////////
                      ERC20 METADATA 
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                      INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _getActive(uint256 configData) internal pure returns (bool) {
        return configData & ~ACTIVE_MASK != 0;
    }

    function _getFrozen(uint256 configData) internal pure returns (bool) {
        return configData & ~FROZEN_MASK != 0;
    }
}