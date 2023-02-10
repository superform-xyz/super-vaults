// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IPool} from "./external/IPool.sol";
import {IRewardsController} from "./external/IRewardsController.sol";

import {DexSwap} from "./utils/swapUtils.sol";

/// @title AaveV3ERC4626Reinvest - extended implementation of yield-daddy @author zefram.eth
/// @dev Reinvests rewards accrued for higher APY
/// @notice ERC4626 wrapper for Aave V3 with rewards reinvesting
contract AaveV3ERC4626Reinvest is ERC4626 {
    /// @notice Manager for setting swap routes for harvest()
    address public manager;

    /// @notice Check if rewards have been set before harvest() and setRoutes()
    bool public rewardsSet;

    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event ClaimRewards(uint256 amount);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error MIN_AMOUNT_ERROR();
    error INVALID_AMOUNT_INPUT_ERROR();

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint256 internal constant DECIMALS_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFF;
    uint256 internal constant ACTIVE_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFF;
    uint256 internal constant FROZEN_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFFFFFFFFFFFFFF;
    uint256 internal constant PAUSED_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFFF;
    uint256 internal constant SUPPLY_CAP_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFF000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    uint256 internal constant SUPPLY_CAP_START_BIT_POSITION = 116;
    uint256 internal constant RESERVE_DECIMALS_START_BIT_POSITION = 48;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The Aave aToken contract
    ERC20 public immutable aToken;

    /// @notice The Aave Pool contract
    IPool public immutable lendingPool;

    /// @notice The Aave RewardsController contract
    IRewardsController public immutable rewardsController;

    /// @notice The Aave reward tokens for a pool
    address[] public rewardTokens;

    /// @notice Map rewardToken to its swapInfo for harvest
    mapping(address => swapInfo) public swapInfoMap;

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
        IPool lendingPool_,
        IRewardsController rewardsController_,
        address manager_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        aToken = aToken_;
        lendingPool = lendingPool_;
        rewardsController = rewardsController_;

        /// For all SuperForm AAVE wrappers Factory contract is the manager for the Routes
        manager = manager_;

        /// TODO: tighter checks
        rewardsSet = false;
    }

    /// -----------------------------------------------------------------------
    /// Aave liquidity mining
    /// -----------------------------------------------------------------------

    /// @notice Get all rewards from AAVE market
    /// @dev Call before setting routes
    /// @dev Requires manual management of Routes
    function setRewards() external returns (address[] memory tokens) {
        require(msg.sender == manager, "onlyOwner");
        tokens = rewardsController.getRewardsByAsset(address(aToken));

        for (uint256 i = 0; i < tokens.length; i++) {
            rewardTokens.push(tokens[i]);
        }

        rewardsSet = true;
    }

    /// @notice Set swap routes for selling rewards
    /// @dev Set route for each rewardToken separately
    /// @dev Setting wrong addresses here will revert harvest() calls
    function setRoutes(
        address rewardToken,
        address token,
        address pair1,
        address pair2
    ) external {
        require(msg.sender == manager, "onlyOwner");
        require(rewardsSet, "rewards not set"); /// @dev Soft-check

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            /// @dev if rewardToken given as arg matches any rewardToken found by setRewards()
            ///      set route for that token
            if (rewardTokens[i] == rewardToken) {
                swapInfoMap[rewardToken] = swapInfo(token, pair1, pair2);
            }
        }
    }

    /// @notice Claims liquidity mining rewards from Aave and sends it to this Vault
    function harvest(uint256[] memory minAmounts_) external {
        /// @dev Wrapper exists only for single aToken
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        /// @dev trusting aave
        (
            address[] memory rewardList,
            uint256[] memory claimedAmounts
        ) = rewardsController.claimAllRewards(assets, address(this));

        if(claimedAmounts.length == 0) {
            return;
        }
        else if(claimedAmounts.length != minAmounts_.length ){
            revert INVALID_AMOUNT_INPUT_ERROR();
        }

        /// @dev if pool rewards more than one token
        /// TODO: Better control. Give ability to select what rewards to swap
        for (uint256 i = 0; i < claimedAmounts.length; i++) {
            swapRewards(rewardList[i], claimedAmounts[i], minAmounts_[i]);
        }

        /// reinvest() without minting (no asset.totalSupply() increase == profit)
        afterDeposit(asset.balanceOf(address(this)), 0);
    }

    /// @notice Swap reward token for underlying asset
    function swapRewards(address rewardToken, uint256 earned, uint256 minAmount_) internal {
        /// @dev Used just for approve
        ERC20 rewardToken_ = ERC20(rewardToken);

        swapInfo memory swapMap = swapInfoMap[rewardToken];
        uint256 reinvestAmount;

        /// @dev Swap AAVE-Fork token for asset
        if (swapMap.token == address(asset)) {
            rewardToken_.approve(swapMap.pair1, earned); /// approve only available rewards

            reinvestAmount = DexSwap.swap(
                earned, /// REWARDS amount to swap
                rewardToken, // from REWARD-TOKEN
                address(asset), /// to target underlying of this Vault
                swapMap.pair1 /// pairToken (pool)
            );
            /// If two swaps needed
        } else {
            rewardToken_.approve(swapMap.pair1, earned); /// approve only available rewards

            uint256 swapTokenAmount = DexSwap.swap(
                earned,
                rewardToken, // from AAVE-Fork
                swapMap.token, /// to intermediary token with high liquidity (no direct pools)
                swapMap.pair1 /// pairToken (pool)
            );

            ERC20(swapMap.token).approve(swapMap.pair2, swapTokenAmount);

            reinvestAmount = DexSwap.swap(
                swapTokenAmount,
                swapMap.token, // from received token
                address(asset), /// to target underlying of this Vault
                swapMap.pair2 /// pairToken (pool)
            );
        }
        if(reinvestAmount < minAmount_) {
            revert MIN_AMOUNT_ERROR();
        }
    }

    /// @notice Check how much rewards are available to claim, useful before harvest()
    function getAllRewardsAccrued()
        external
        view
        returns (address[] memory rewardList, uint256[] memory claimedAmounts)
    {
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        (rewardList, claimedAmounts) = rewardsController.getAllUserRewards(
            assets,
            address(this)
        );
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

            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares;
            }
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

            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares;
            }
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
        // TODO: Approve management arc. Save gas for callers
        asset.safeApprove(address(lendingPool), assets);

        // deposit into lendingPool
        lendingPool.supply(address(asset), assets, address(this), 0);
    }

    function maxDeposit(address)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // check if asset is paused
        uint256 configData = lendingPool
            .getReserveData(address(asset))
            .configuration
            .data;
        if (
            !(_getActive(configData) &&
                !_getFrozen(configData) &&
                !_getPaused(configData))
        ) {
            return 0;
        }

        // handle supply cap
        uint256 supplyCapInWholeTokens = _getSupplyCap(configData);
        if (supplyCapInWholeTokens == 0) {
            return type(uint256).max;
        }

        uint8 tokenDecimals = _getDecimals(configData);
        uint256 supplyCap = supplyCapInWholeTokens * 10**tokenDecimals;
        return supplyCap - aToken.totalSupply();
    }

    function maxMint(address) public view virtual override returns (uint256) {
        // check if asset is paused
        uint256 configData = lendingPool
            .getReserveData(address(asset))
            .configuration
            .data;
        if (
            !(_getActive(configData) &&
                !_getFrozen(configData) &&
                !_getPaused(configData))
        ) {
            return 0;
        }

        // handle supply cap
        uint256 supplyCapInWholeTokens = _getSupplyCap(configData);
        if (supplyCapInWholeTokens == 0) {
            return type(uint256).max;
        }

        uint8 tokenDecimals = _getDecimals(configData);
        uint256 supplyCap = supplyCapInWholeTokens * 10**tokenDecimals;
        return convertToShares(supplyCap - aToken.totalSupply());
    }

    function maxWithdraw(address owner)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // check if asset is paused
        uint256 configData = lendingPool
            .getReserveData(address(asset))
            .configuration
            .data;
        if (!(_getActive(configData) && !_getPaused(configData))) {
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
        // check if asset is paused
        uint256 configData = lendingPool
            .getReserveData(address(asset))
            .configuration
            .data;
        if (!(_getActive(configData) && !_getPaused(configData))) {
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
        vaultName = string.concat("ERC4626-Wrapped Aave v3 ", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultSymbol)
    {
        vaultSymbol = string.concat("wa", asset_.symbol());
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _getDecimals(uint256 configData) internal pure returns (uint8) {
        return
            uint8(
                (configData & ~DECIMALS_MASK) >>
                    RESERVE_DECIMALS_START_BIT_POSITION
            );
    }

    function _getActive(uint256 configData) internal pure returns (bool) {
        return configData & ~ACTIVE_MASK != 0;
    }

    function _getFrozen(uint256 configData) internal pure returns (bool) {
        return configData & ~FROZEN_MASK != 0;
    }

    function _getPaused(uint256 configData) internal pure returns (bool) {
        return configData & ~PAUSED_MASK != 0;
    }

    function _getSupplyCap(uint256 configData) internal pure returns (uint256) {
        return (configData & ~SUPPLY_CAP_MASK) >> SUPPLY_CAP_START_BIT_POSITION;
    }
}
