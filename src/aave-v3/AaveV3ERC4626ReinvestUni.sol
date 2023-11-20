// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.23;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IPool} from "./external/IPool.sol";
import {IRewardsController} from "./external/IRewardsController.sol";

import {DexSwap} from "../_global/swapUtils.sol";
import {ISwapRouter} from "../aave-v2/utils/ISwapRouter.sol";

/// @title AaveV3ERC4626ReinvestUni -
/// @notice xtended implementation of yield-daddy ERC4626 wrapper for Aave V3 with rewards reinvesting
/// Reinvests rewards accrued for higher APY
/// @author ZeroPoint Labs
contract AaveV3ERC4626ReinvestUni is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                      LIBRARIES USAGE
    //////////////////////////////////////////////////////////////*/

    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                      ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when swap path fee in reinvest is invalid.
    error INVALID_FEE();
    /// @notice Thrown when trying to call a permissioned function with an invalid access
    error INVALID_ACCESS();
    /// @notice When rewardsSet is false
    error REWARDS_NOT_SET();
    /// @notice Thrown when trying to redeem shares worth 0 assets
    error ZERO_ASSETS();

    /*//////////////////////////////////////////////////////////////
                      CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant DECIMALS_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFF;
    uint256 internal constant ACTIVE_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFF;
    uint256 internal constant FROZEN_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFFFFFFFFFFFFFF;
    uint256 internal constant PAUSED_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFFF;
    uint256 internal constant SUPPLY_CAP_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFF000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    uint256 internal constant SUPPLY_CAP_START_BIT_POSITION = 116;
    uint256 internal constant RESERVE_DECIMALS_START_BIT_POSITION = 48;

    /*//////////////////////////////////////////////////////////////
                      IMMUATABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The Aave aToken contract
    ERC20 public immutable aToken;

    /// @notice The Aave Pool contract
    IPool public immutable lendingPool;

    /// @notice The Aave RewardsController contract
    IRewardsController public immutable rewardsController;

    /// @notice The Aave reward tokens for a pool
    address[] public rewardTokens;

    /// @notice Map rewardToken to its swapInfo for harvest
    mapping(address => bytes) public swapInfoMap;

    ISwapRouter public immutable swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /// @notice Manager for setting swap routes for harvest()
    address public manager;

    /// @notice Check if rewards have been set before harvest() and setRoutes()
    bool public rewardsSet;

    /*//////////////////////////////////////////////////////////////
                      CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Construct a new AaveV3ERC4626ReinvestUni contract
    /// @param asset_ The underlying asset
    /// @param aToken_ The Aave aToken contract
    /// @param lendingPool_ The Aave Pool contract
    /// @param rewardsController_ The Aave RewardsController contract
    /// @param manager_ The manager for setting swap routes for harvest()
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

    /*//////////////////////////////////////////////////////////////
                      AAVE LIQUIDITY MINING
    //////////////////////////////////////////////////////////////*/

    /// @notice Get all rewards from AAVE market
    /// @dev Call before setting routes
    /// @dev Requires manual management of Routes
    function setRewards() external returns (address[] memory tokens) {
        if (msg.sender != manager) revert INVALID_ACCESS();
        tokens = rewardsController.getRewardsByAsset(address(aToken));

        for (uint256 i = 0; i < tokens.length; i++) {
            rewardTokens.push(tokens[i]);
        }

        rewardsSet = true;
    }

    /// @notice Set swap routes for selling rewards
    /// @dev Set route for each rewardToken separately
    /// @dev Setting wrong addresses here will revert harvest() calls
    /// @param rewardToken_ The reward token to set route for
    /// @param poolFee1_ The fee for the first pool
    /// @param tokenMid_ The token to swap to before the second pool
    /// @param poolFee2_ The fee for the second pool
    function setRoutes(address rewardToken_, uint24 poolFee1_, address tokenMid_, uint24 poolFee2_) external {
        if (msg.sender != manager) revert INVALID_ACCESS();
        if (!rewardsSet) revert REWARDS_NOT_SET();
        /// @dev Soft-check
        if (poolFee1_ == 0) revert INVALID_FEE();
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            /// @dev if rewardToken given as arg matches any rewardToken found by setRewards()
            ///      set route for that token
            if (rewardTokens[i] == rewardToken_) {
                if (poolFee2_ == 0 || tokenMid_ == address(0)) {
                    swapInfoMap[rewardToken_] = abi.encodePacked(rewardToken_, poolFee1_, address(asset));
                } else {
                    swapInfoMap[rewardToken_] =
                        abi.encodePacked(rewardToken_, poolFee1_, tokenMid_, poolFee2_, address(asset));
                }
            }
        }
    }

    /// @notice Claims liquidity mining rewards from Aave and sends it to this Vault
    /// @param minAmountOuts_ The minimum amount of underlying asset to receive for each reward token
    function harvest(uint256[] calldata minAmountOuts_) external {
        /// @dev Wrapper exists only for single aToken
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        /// @dev trusting aave
        (address[] memory rewardList, uint256[] memory claimedAmounts) =
            rewardsController.claimAllRewards(assets, address(this));

        /// @dev if pool rewards more than one token
        /// TODO: Better control. Give ability to select what rewards to swap
        for (uint256 i = 0; i < claimedAmounts.length; i++) {
            swapRewards(rewardList[i], claimedAmounts[i], minAmountOuts_[i]);
        }
    }

    /// @notice Swap reward token for underlying asset
    function swapRewards(address rewardToken_, uint256 earned_, uint256 minAmountOut_) internal {
        /// @dev Used just for approve
        ERC20 rewardToken = ERC20(rewardToken_);

        bytes memory swapMap = swapInfoMap[rewardToken_];

        rewardToken.approve(address(swapRouter), earned_);
        /// @dev Swap rewards to asset
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: swapMap,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: earned_,
            amountOutMinimum: minAmountOut_
        });

        // Executes the swap.
        swapRouter.exactInput(params);
        /// reinvest() without minting (no asset.totalSupply() increase == profit)
        afterDeposit(asset.balanceOf(address(this)), 0);
    }

    /// @notice Check how much rewards are available to claim, useful before harvest()
    function getAllRewardsAccrued()
        external
        view
        returns (address[] memory rewardList, uint256[] memory claimedAmounts)
    {
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        (rewardList, claimedAmounts) = rewardsController.getAllUserRewards(assets, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                      ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function withdraw(uint256 assets_, address receiver_, address owner_)
        public
        virtual
        override
        returns (uint256 shares)
    {
        shares = previewWithdraw(assets_); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) {
                allowance[owner_][msg.sender] = allowed - shares;
            }
        }

        beforeWithdraw(assets_, shares);

        _burn(owner_, shares);

        emit Withdraw(msg.sender, receiver_, owner_, assets_, shares);

        // withdraw assets directly from Aave
        lendingPool.withdraw(address(asset), assets_, receiver_);
    }

    function redeem(uint256 shares_, address receiver_, address owner_)
        public
        virtual
        override
        returns (uint256 assets)
    {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) {
                allowance[owner_][msg.sender] = allowed - shares_;
            }
        }

        // Check for rounding error since we round down in previewRedeem.
        if ((assets = previewRedeem(shares_)) == 0) {
            revert ZERO_ASSETS();
        }

        beforeWithdraw(assets, shares_);

        _burn(owner_, shares_);

        emit Withdraw(msg.sender, receiver_, owner_, assets, shares_);

        // withdraw assets directly from Aave
        lendingPool.withdraw(address(asset), assets, receiver_);
    }

    function totalAssets() public view virtual override returns (uint256) {
        // aTokens use rebasing to accrue interest, so the total assets is just the aToken balance
        return aToken.balanceOf(address(this));
    }

    function afterDeposit(uint256 assets_, uint256 /*shares*/ ) internal virtual override {
        // approve to lendingPool
        // TODO: Approve management arc. Save gas for callers
        asset.safeApprove(address(lendingPool), assets_);

        // deposit into lendingPool
        lendingPool.supply(address(asset), assets_, address(this), 0);
    }

    function maxDeposit(address) public view virtual override returns (uint256) {
        // check if asset is paused
        uint256 configData = lendingPool.getReserveData(address(asset)).configuration.data;
        if (!(_getActive(configData) && !_getFrozen(configData) && !_getPaused(configData))) {
            return 0;
        }

        // handle supply cap
        uint256 supplyCapInWholeTokens = _getSupplyCap(configData);
        if (supplyCapInWholeTokens == 0) {
            return type(uint256).max;
        }

        uint8 tokenDecimals = _getDecimals(configData);
        uint256 supplyCap = supplyCapInWholeTokens * 10 ** tokenDecimals;
        if (aToken.totalSupply() >= supplyCap) return 0;
        return supplyCap - aToken.totalSupply();
    }

    function maxMint(address) public view virtual override returns (uint256) {
        // check if asset is paused
        uint256 configData = lendingPool.getReserveData(address(asset)).configuration.data;
        if (!(_getActive(configData) && !_getFrozen(configData) && !_getPaused(configData))) {
            return 0;
        }

        // handle supply cap
        uint256 supplyCapInWholeTokens = _getSupplyCap(configData);
        if (supplyCapInWholeTokens == 0) {
            return type(uint256).max;
        }

        uint8 tokenDecimals = _getDecimals(configData);
        uint256 supplyCap = supplyCapInWholeTokens * 10 ** tokenDecimals;
        if (aToken.totalSupply() >= supplyCap) return 0;
        return convertToShares(supplyCap - aToken.totalSupply());
    }

    function maxWithdraw(address owner_) public view virtual override returns (uint256) {
        // check if asset is paused
        uint256 configData = lendingPool.getReserveData(address(asset)).configuration.data;
        if (!(_getActive(configData) && !_getPaused(configData))) {
            return 0;
        }

        uint256 cash = asset.balanceOf(address(aToken));
        uint256 assetsBalance = convertToAssets(balanceOf[owner_]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    function maxRedeem(address owner_) public view virtual override returns (uint256) {
        // check if asset is paused
        uint256 configData = lendingPool.getReserveData(address(asset)).configuration.data;
        if (!(_getActive(configData) && !_getPaused(configData))) {
            return 0;
        }

        uint256 cash = asset.balanceOf(address(aToken));
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner_];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    /*//////////////////////////////////////////////////////////////
                      METADATA
    //////////////////////////////////////////////////////////////*/

    function _vaultName(ERC20 asset_) internal view virtual returns (string memory vaultName) {
        vaultName = string.concat("ERC4626-Wrapped Aave v3 ", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_) internal view virtual returns (string memory vaultSymbol) {
        vaultSymbol = string.concat("wa", asset_.symbol());
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _getDecimals(uint256 configData_) internal pure returns (uint8) {
        return uint8((configData_ & ~DECIMALS_MASK) >> RESERVE_DECIMALS_START_BIT_POSITION);
    }

    function _getActive(uint256 configData_) internal pure returns (bool) {
        return configData_ & ~ACTIVE_MASK != 0;
    }

    function _getFrozen(uint256 configData_) internal pure returns (bool) {
        return configData_ & ~FROZEN_MASK != 0;
    }

    function _getPaused(uint256 configData_) internal pure returns (bool) {
        return configData_ & ~PAUSED_MASK != 0;
    }

    function _getSupplyCap(uint256 configData_) internal pure returns (uint256) {
        return (configData_ & ~SUPPLY_CAP_MASK) >> SUPPLY_CAP_START_BIT_POSITION;
    }
}
