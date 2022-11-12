// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IPool} from "./external/IPool.sol";
import {IRewardsController} from "./external/IRewardsController.sol";

import {DexSwap} from "../../utils/swapUtils.sol";

/// @title AaveV3ERC4626Reinvest - extended implementation of yield-daddy @author zefram.eth
/// @dev Reinvests rewards accrued for higher APY
/// @notice ERC4626 wrapper for Aave V3
/// @dev Important security note: due to Aave using a rebasing model for aTokens,
/// this contract cannot independently keep track of the deposited funds, so it is possible
/// for an attacker to directly transfer aTokens to this contract, increase the vault share
/// price atomically, and then exploit an external lending market that uses this contract
/// as collateral.
contract AaveV3ERC4626Reinvest is ERC4626 {
    address public manager;

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

    /// @notice The address that will receive the liquidity mining rewards (if any)
    address public immutable rewardRecipient;

    /// @notice The Aave RewardsController contract
    IRewardsController public immutable rewardsController;

    /// @notice The Aave reward tokens for a pool
    ERC20[] public rewardTokens;

    /// @notice Map rewardToken to its swapInfo for harvest
    mapping(ERC20 => swapInfo) public swapInfoMap;

    /// @notice Pointer to swapInfo
    swapInfo public SwapInfo;

    /// Compact struct to make two swaps (on Uniswap v2)
    /// A => B (using pair1) then B => asset (of Wrapper) (using pair2)
    /// will work fine as long we only get 1 type of reward token
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
        address rewardRecipient_,
        IRewardsController rewardsController_,
        address manager_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        aToken = aToken_;
        lendingPool = lendingPool_;
        rewardRecipient = rewardRecipient_;
        rewardsController = rewardsController_;
        manager = manager_;

        rewardsSet = false;
    }

    /// -----------------------------------------------------------------------
    /// Aave liquidity mining
    /// -----------------------------------------------------------------------

    function setRewards() external {
        require(msg.sender == manager, "onlyOwner");
        address[] memory tokens = rewardsController.getRewardsByAsset(
            address(aToken)
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            rewardTokens.push(ERC20(tokens[i]));
        }

        rewardsSet = true;
    }

    function setRoutes(
        ERC20 rewardToken,
        address token,
        address pair1,
        address pair2
    ) external {
        require(msg.sender == manager, "onlyOwner");
        require(rewardsSet, "rewards not set");

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] == rewardToken) {
                swapInfoMap[rewardToken] = swapInfo(token, pair1, pair2);

                rewardToken.approve(SwapInfo.pair1, type(uint256).max); /// max approves address
                ERC20(SwapInfo.token).approve(
                    SwapInfo.pair2,
                    type(uint256).max
                );
            }
        }
    }

    /// @notice Claims liquidity mining rewards from Aave and sends it to rewardRecipient
    function harvest() external {
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        /// @dev trusting aave here
        (
            address[] memory rewardList,
            uint256[] memory claimedAmounts
        ) = rewardsController.claimAllRewards(assets, address(this));

        /// @dev if pool rewards more than one token
        if (claimedAmounts.length == 1) {
            swap(rewardList[0], claimedAmounts[0]);
        } else {
            for (uint256 i = 0; i < claimedAmounts.length; i++) {
                swap(rewardList[i], claimedAmounts[i]);
            }
        }
    }

    function swap(address rewardToken, uint256 earned) internal {
        swapInfo memory swapMap = swapInfoMap[ERC20(rewardToken)];
        /// If one swap needed (high liquidity pair) - set swapInfo.token0/token/pair2 to 0x
        /// @dev Swap AAVE-Fork token for asset
        if (SwapInfo.token == address(asset)) {
            DexSwap.swap(
                earned, /// REWARDS amount to swap
                rewardToken, // from REWARD-TOKEN
                address(asset), /// to target underlying of this Vault
                swapMap.pair1 /// pairToken (pool)
            );
            /// If two swaps needed
        } else {
            uint256 swapTokenAmount = DexSwap.swap(
                earned,
                rewardToken, // from AAVE-Fork
                swapMap.token, /// to intermediary token with high liquidity (no direct pools)
                swapMap.pair1 /// pairToken (pool)
            );

            swapTokenAmount = DexSwap.swap(
                swapTokenAmount,
                swapMap.token, // from received token
                address(asset), /// to target underlying of this Vault
                swapMap.pair2 /// pairToken (pool)
            );
        }

        /// reinvest() without minting (no asset.totalSupply() increase == profit)
        /// afterDeposit just makes totalAssets() aToken's balance growth (to be distributed back to share owners)
        afterDeposit(asset.balanceOf(address(this)), 0);
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
