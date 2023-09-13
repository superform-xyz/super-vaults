// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "solmate/mixins/ERC4626.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

import { ICERC20 } from "./external/ICERC20.sol";
import { LibCompound } from "./external/LibCompound.sol";
import { IComptroller } from "./external/IComptroller.sol";
import { ISwapRouter } from "../aave-v2/utils/ISwapRouter.sol";
import { DexSwap } from "../_global/swapUtils.sol";

/// @title CompoundV2ERC4626Wrapper
/// @notice Custom implementation of yield-daddy wrappers with flexible reinvesting logic
/// @notice Rationale: Forked protocols often implement custom functions and modules on top of forked code.
/// @author ZeroPoint Labs
contract CompoundV2ERC4626Wrapper is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                            LIBRARIES USAGE
    //////////////////////////////////////////////////////////////*/

    using LibCompound for ICERC20;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a call to Compound returned an error.
    /// @param errorCode The error code returned by Compound
    error COMPOUND_ERROR(uint256 errorCode);
    /// @notice Thrown when reinvest amount is not enough.
    error MIN_AMOUNT_ERROR();
    /// @notice Thrown when caller is not the manager.
    error INVALID_ACCESS_ERROR();
    /// @notice Thrown when swap path fee in reinvest is invalid.
    error INVALID_FEE_ERROR();

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant NO_ERROR = 0;

    /*//////////////////////////////////////////////////////////////
                        IMMUTABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Access Control for harvest() route
    address public immutable manager;

    /// @notice The COMP-like token contract
    ERC20 public immutable reward;

    /// @notice The Compound cToken contract
    ICERC20 public immutable cToken;

    /// @notice The Compound comptroller contract
    IComptroller public immutable comptroller;

    /// @notice Pointer to swapInfo
    bytes public swapPath;

    ISwapRouter public immutable swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /// Compact struct to make two swaps (PancakeSwap on BSC)
    /// A => B (using pair1) then B => asset (of Wrapper) (using pair2)
    struct swapInfo {
        address token;
        address pair1;
        address pair2;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor for the CompoundV2ERC4626Wrapper
    /// @param asset_ The address of the underlying asset
    /// @param reward_ The address of the reward token
    /// @param cToken_ The address of the cToken
    /// @param comptroller_ The address of the comptroller
    /// @param manager_ The address of the manager
    constructor(
        ERC20 asset_, // underlying
        ERC20 reward_, // comp token or other
        ICERC20 cToken_, // compound concept of a share
        IComptroller comptroller_,
        address manager_
    )
        ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_))
    {
        reward = reward_;
        cToken = cToken_;
        comptroller = comptroller_;
        manager = manager_;
        ICERC20[] memory cTokens = new ICERC20[](1);
        cTokens[0] = cToken;
        comptroller.enterMarkets(cTokens);
    }

    /*//////////////////////////////////////////////////////////////
                            REWARDS
    //////////////////////////////////////////////////////////////*/

    /// @notice sets the swap path for reinvesting rewards
    /// @param poolFee1_ fee for first swap
    /// @param tokenMid_ token for first swap
    /// @param poolFee2_ fee for second swap
    function setRoute(uint24 poolFee1_, address tokenMid_, uint24 poolFee2_) external {
        if (msg.sender != manager) revert INVALID_ACCESS_ERROR();
        if (poolFee1_ == 0) revert INVALID_FEE_ERROR();
        if (poolFee2_ == 0 || tokenMid_ == address(0)) {
            swapPath = abi.encodePacked(reward, poolFee1_, address(asset));
        } else {
            swapPath = abi.encodePacked(reward, poolFee1_, tokenMid_, poolFee2_, address(asset));
        }
        ERC20(reward).approve(address(swapRouter), type(uint256).max);
        /// max approve
    }

    /// @notice Claims liquidity mining rewards from Compound and performs low-lvl swap with instant reinvesting
    /// Calling harvest() claims COMP-Fork token through direct Pair swap for best control and lowest cost
    /// harvest() can be called by anybody. ideally this function should be adjusted per needs (e.g add fee for
    /// harvesting)
    function harvest(uint256 minAmountOut_) external {
        ICERC20[] memory cTokens = new ICERC20[](1);
        cTokens[0] = cToken;
        comptroller.claimComp(address(this), cTokens);

        uint256 earned = ERC20(reward).balanceOf(address(this));
        uint256 reinvestAmount;
        /// @dev Swap rewards to asset
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: swapPath,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: earned,
            amountOutMinimum: minAmountOut_
        });

        // Executes the swap.
        reinvestAmount = swapRouter.exactInput(params);
        if (reinvestAmount < minAmountOut_) {
            revert MIN_AMOUNT_ERROR();
        }
        afterDeposit(asset.balanceOf(address(this)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDES
    We can't inherit directly from Yield-daddy because of rewardClaim lock
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view virtual override returns (uint256) {
        return cToken.viewUnderlyingBalanceOf(address(this));
    }

    function beforeWithdraw(uint256 assets_, uint256 /*shares*/ ) internal virtual override {
        uint256 errorCode = cToken.redeemUnderlying(assets_);
        if (errorCode != NO_ERROR) {
            revert COMPOUND_ERROR(errorCode);
        }
    }

    function afterDeposit(uint256 assets_, uint256 /*shares*/ ) internal virtual override {
        // approve to cToken
        asset.safeApprove(address(cToken), assets_);
        // deposit into cToken
        uint256 errorCode = cToken.mint(assets_);
        if (errorCode != NO_ERROR) {
            revert COMPOUND_ERROR(errorCode);
        }
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(cToken)) return 0;
        return type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(cToken)) return 0;
        return type(uint256).max;
    }

    function maxWithdraw(address owner_) public view override returns (uint256) {
        uint256 cash = cToken.getCash();
        uint256 assetsBalance = convertToAssets(balanceOf[owner_]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    function maxRedeem(address owner_) public view override returns (uint256) {
        uint256 cash = cToken.getCash();
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner_];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 METADATA
    //////////////////////////////////////////////////////////////*/

    function _vaultName(ERC20 asset_) internal view virtual returns (string memory vaultName) {
        vaultName = string.concat("CompStratERC4626- ", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_) internal view virtual returns (string memory vaultSymbol) {
        vaultSymbol = string.concat("cS-", asset_.symbol());
    }
}
