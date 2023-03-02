// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "../interfaces/IUniswapV2Router.sol";
import {UniswapV2Library} from "../utils/UniswapV2Library.sol";

import {IUniswapV3Pool} from "../interfaces/IUniswapV3.sol";

import {DexSwap} from "../utils/swapUtils.sol";

/// @title UniswapV2ERC4626Swap
/// @notice ERC4626 UniswapV2 Adapter - Allows exit & join to UniswapV2 LP Pools from ERC4626 interface. Single sided liquidity adapter.
/// @notice Provides a set of helpful functions to calculate different aspects of liquidity providing to the UniswapV2-style pools.
/// @notice Accept tokenX || tokenY as ASSET. Uses UniswapV2Pair LP-TOKEN as AUM (totalAssets()).
/// @notice BASIC FLOW: Deposit tokenX > tokenX swap to tokenX && tokenY optimal amount > tokenX/Y deposited into UniswapV2
/// @notice > shares minted to the Vault from the Uniswap Pool > shares minted to the user from the Vault
/// @dev Example Pool: https://v2.info.uniswap.org/pair/0xae461ca67b15dc8dc81ce7615e0320da1a9ab8d5 (DAI-USDC LP/PAIR on ETH).
/// @author ZeroPoint Labs
contract UniswapV2ERC4626Swap is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                            LIBRARIES USAGE
    //////////////////////////////////////////////////////////////*/

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Shares are lower than the minimum required.
    error NOT_MIN_SHARES_OUT();

    /// @notice Amount is lower than the minimum required.
    error NOT_MIN_AMOUNT_OUT();

    /// @notice Thrown when trying to deposit 0 assets
    error ZERO_ASSETS();

    /*//////////////////////////////////////////////////////////////
                      IMMUATABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable manager;

    /// NOTE: Hardcoded workaround to ensure execution within changing pair reserves - 0.4% (4000/1000000)
    uint256 public fee = 4000;
    uint256 public immutable slippageFloat = 1000000;

    IUniswapV2Pair public immutable pair;
    IUniswapV2Router public immutable router;
    IUniswapV3Pool public immutable oracle;

    ERC20 public token0;
    ERC20 public token1;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Construct a new UniswapV2ERC4626Swap contract.
    /// @param asset_ The address of the ERC20 token to be used as ASSET.
    /// @param name_ The name of the ERC4626 token.
    /// @param symbol_ The symbol of the ERC4626 token.
    /// @param router_ The address of the UniswapV2Router.
    /// @param pair_ The address of the UniswapV2Pair.
    /// @param oracle_ The address of the UniswapV3Pool.
    constructor(
        ERC20 asset_,
        string memory name_,
        string memory symbol_,
        IUniswapV2Router router_,
        IUniswapV2Pair pair_,
        IUniswapV3Pool oracle_
    ) ERC4626(asset_, name_, symbol_) {
        manager = msg.sender;

        pair = pair_;
        router = router_;
        oracle = oracle_;

        address token0_ = pair.token0();
        address token1_ = pair.token1();

        if (address(asset) == token0_) {
            token0 = asset;
            token1 = ERC20(token1_);
        } else {
            token0 = ERC20(token0_);
            token1 = asset;
        }
    }

    /// @notice Remove liquidity from the underlying UniswapV2Pair. Receive both token0 and token1 on the Vault address.
    function _liquidityRemove(uint256, uint256 shares_)
        internal
        returns (uint256 assets0, uint256 assets1)
    {
        /// @dev Values are sorted because we sort if t0/t1 == asset at runtime
        (assets0, assets1) = getAssetsAmounts(shares_);

        pair.approve(address(router), shares_);

        /// temp implementation, we should call directly on a pair
        (assets0, assets1) = router.removeLiquidity(
            address(token0),
            address(token1),
            shares_,
            assets0 - _getSlippage(assets0), /// NOTE: No MEV protection, only ensuring execution within certain range to avoid reverts
            assets1 - _getSlippage(assets1), /// NOTE: No MEV protection, only ensuring execution within certain range to avoid reverts
            address(this),
            block.timestamp + 100 /// temp implementation
        );
    }

    /// @notice Add liquidity to the underlying UniswapV2Pair. Send both token0 and token1 from the Vault address.
    function _liquidityAdd(uint256 assets0_, uint256 assets1_)
        internal
        returns (uint256 li)
    {
        /// temp should be more elegant. better than max approve though
        token0.approve(address(router), assets0_);
        token1.approve(address(router), assets1_);

        /// temp implementation, we should call directly on a pair
        (, , li) = router.addLiquidity(
            address(token0),
            address(token1),
            assets0_,
            assets1_,
            assets0_ - _getSlippage(assets0_), /// NOTE: No MEV protection, only ensuring execution within certain range to avoid reverts
            assets1_ - _getSlippage(assets1_), /// NOTE: No MEV protection, only ensuring execution within certain range to avoid reverts
            address(this),
            block.timestamp + 100 /// temp implementation
        );
    }

    /// @notice Non-ERC4626 deposit function taking additional protection parameters for execution
    /// @dev Caller can calculate minSharesOut using previewDeposit function range of outputs
    function deposit(
        uint256 assets_,
        address receiver_,
        uint256 minSharesOut_
    ) public returns (uint256 shares) {
        asset.safeTransferFrom(msg.sender, address(this), assets_);

        /// @dev caller calculates minSwapOut from uniswapV2Library off-chain, reverts if swap is manipulated
        (uint256 a0, uint256 a1) = _swapJoin(assets_);

        shares = _liquidityAdd(a0, a1);

        /// @dev caller calculates minSharesOut off-chain, this contracts functions can be used to retrive reserves over the past blocks
        if (shares < minSharesOut_) revert NOT_MIN_SHARES_OUT();

        /// @dev we just pass uniswap lp-token amount to user
        _mint(receiver_, shares);

        emit Deposit(msg.sender, receiver_, assets_, shares);
    }

    /// @notice receives tokenX of UniV2 pair and mints shares of this vault for deposited tokenX/Y into UniV2 pair
    /// @dev unsecure deposit function, trusting external asset reserves
    /// @dev Standard ERC4626 deposit is prone to manipulation because of no minSharesOut argument allowed
    /// @dev Caller can calculate shares through previewDeposit and trust previewDeposit returned value to revert here
    function deposit(uint256 assets_, address receiver_)
        public
        override
        returns (uint256 shares)
    {
        /// @dev can be manipulated before making deposit() call
        /// NOTE: Re-think if calling this after _swapJoin() and _liquidityAdd() is better
        /// NOTE: What if we would call two times and check delta between outputs? May be just another weak validation
        shares = previewDeposit(assets_);

        /// @dev 100% of tokenX/Y is transferred to this contract
        asset.safeTransferFrom(msg.sender, address(this), assets_);

        /// @dev swap from 100% to ~50% of tokenX/Y
        /// NOTE: Can be manipulated if caller manipulated reserves before deposit() call
        /// NOTE: Is there a risk in inflating this _swapJoin() call? It will generate fees for holders of shares
        (uint256 a0, uint256 a1) = _swapJoin(assets_);

        /// NOTE: Pool reserve could be manipulated
        /// NOTE: reserve manipulation, leading to inflation of shares is meaningless, because redemption happens against UniV2Pair not this Vault balance
        uint256 uniShares = _liquidityAdd(a0, a1);

        /// @dev totalAssets holds sum of all UniLP,
        /// NOTE: UniLP is non-rebasing, yield accrues on Uniswap pool (you can redeem more t0/t1 for same amount of LP)
        /// NOTE: If we want it as Strategy, e.g do something with this LP, then we need to calculate shares, 1:1 won't work
        /// NOTE: Caller needs to trust previewDeposit return value which can be manipulated for 1 block
        if (uniShares < shares) revert NOT_MIN_SHARES_OUT();

        /// @dev we want to have 1:1 relation to UniV2Pair lp token
        shares = uniShares;

        /// NOTE: TBD: oracle or smth else
        // (uint256 lowBound, uint256 highBound) = getAvgPriceBound();
        // require((uniShares >= lowBound && uniShares <= highBound), "SHARES_AMOUNT_OUT");

        _mint(receiver_, uniShares);

        emit Deposit(msg.sender, receiver_, assets_, uniShares);
    }

    /// @notice Non-ERC4626 mint function taking additional protection parameters for execution
    function mint(
        uint256 shares_,
        address receiver_,
        uint256 minSharesOut_
    ) public returns (uint256 assets) {
        assets = previewMint(shares_);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        (uint256 a0, uint256 a1) = _swapJoin(assets);

        uint256 uniShares = _liquidityAdd(a0, a1);

        /// @dev Protected mint, caller can calculate minSharesOut off-chain
        if (uniShares < minSharesOut_) revert NOT_MIN_SHARES_OUT();

        _mint(receiver_, uniShares);

        emit Deposit(msg.sender, receiver_, assets, uniShares);
    }

    /// @notice mint exact amount of this Vault shares and effectivley UniswapV2Pair shares (1:1 relation)
    /// @dev Requires caller to have a prior knowledge of what amount of `assets` to approve (use this contract helper functions)
    function mint(uint256 shares_, address receiver_)
        public
        override
        returns (uint256 assets)
    {
        assets = previewMint(shares_);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        (uint256 a0, uint256 a1) = _swapJoin(assets);

        uint256 uniShares = _liquidityAdd(a0, a1);

        /// NOTE: PreviewMint needs to output reasonable amount of shares
        if (uniShares < shares_) revert NOT_MIN_SHARES_OUT();

        _mint(receiver_, uniShares);

        emit Deposit(msg.sender, receiver_, assets, uniShares);
    }

    /// @notice Non-ERC4626 withdraw function taking additional protection parameters for execution
    /// @dev Caller specifies minAmountOut_ of this Vault's underlying to receive for burning Vault's shares (and UniswapV2Pair shares)
    function withdraw(
        uint256 assets_,
        address receiver_,
        address owner_,
        uint256 minAmountOut_ /// @dev calculated off-chain, "secure" withdraw function.
    ) public returns (uint256 shares) {
        shares = previewWithdraw(assets_);

        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares;
        }

        (uint256 assets0, uint256 assets1) = _liquidityRemove(assets_, shares);

        _burn(owner_, shares);

        uint256 amount = asset == token0
            ? _swapExit(assets1) + assets0
            : _swapExit(assets0) + assets1;

        /// @dev Protected amountOut check
        if (amount < minAmountOut_) revert NOT_MIN_AMOUNT_OUT();

        asset.safeTransfer(receiver_, amount);

        emit Withdraw(msg.sender, receiver_, owner_, amount, shares);
    }

    /// @notice Receive amount of `assets` of underlying token of this Vault (token0 or token1 of underlying UniswapV2Pair)
    function withdraw(
        uint256 assets_,
        address receiver_,
        address owner_
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets_);

        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares;
        }

        (uint256 assets0, uint256 assets1) = _liquidityRemove(assets_, shares);

        _burn(owner_, shares);

        /// @dev ideally contract for token0/1 should know what assets amount to use without conditional checks, gas overhead
        uint256 amount = asset == token0
            ? _swapExit(assets1) + assets0
            : _swapExit(assets0) + assets1;

        /// NOTE: This is a weak check anyways. previews can be manipulated.
        /// NOTE: If enabled, withdraws() which didn't accrue enough of the yield to cover deposit's _swapJoin() will fail
        /// NOTE: For secure execution user should use protected functions
        /// require(amount >= assets, "ASSETS_AMOUNT_OUT");

        asset.safeTransfer(receiver_, amount);

        emit Withdraw(msg.sender, receiver_, owner_, amount, shares);
    }

    /// @notice Non-ERC4626 redeem function taking additional protection parameters for execution
    /// @dev Caller needs to know the amount of minAmountOut to receive for burning amount of shares beforehand
    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_,
        uint256 minAmountOut_ /// @dev calculated off-chain, "secure" withdraw function.
    ) public returns (uint256 assets) {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares_;
        }

        if ((assets = previewRedeem(shares_)) == 0) revert ZERO_ASSETS();

        (uint256 assets0, uint256 assets1) = _liquidityRemove(assets, shares_);

        _burn(owner_, shares_);

        uint256 amount = asset == token0
            ? _swapExit(assets1) + assets0
            : _swapExit(assets0) + assets1;

        /// @dev Protected amountOut check
        if (amount < minAmountOut_) revert NOT_MIN_AMOUNT_OUT();

        asset.safeTransfer(receiver_, amount);

        emit Withdraw(msg.sender, receiver_, owner_, amount, shares_);
    }

    /// @notice Burn amount of 'shares' of this Vault (and UniswapV2Pair shares) to receive some amount of underlying token of this vault
    function redeem(
        uint256 shares_,
        address receiver_,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares_;
        }

        // Check for rounding error since we round down in previewRedeem.
        if ((assets = previewRedeem(shares_)) == 0) revert ZERO_ASSETS();

        (uint256 assets0, uint256 assets1) = _liquidityRemove(assets, shares_);

        _burn(owner, shares_);

        /// @dev ideally contract for token0/1 should know what assets amount to use without conditional checks, gas overhead
        uint256 amount = asset == token0
            ? _swapExit(assets1) + assets0
            : _swapExit(assets0) + assets1;

        /// NOTE: See note in withdraw()
        // require(amount >= assets, "ASSETS_AMOUNT_OUT");

        asset.safeTransfer(receiver_, amount);

        emit Withdraw(msg.sender, receiver_, owner, amount, shares_);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice totalAssets is equal to UniswapV2Pair lp tokens minted through this adapter
    function totalAssets() public view override returns (uint256) {
        return pair.balanceOf(address(this));
    }

    /// @notice for this many asset (ie token0) we get this many shares
    function previewDeposit(uint256 assets_)
        public
        view
        override
        returns (uint256 shares)
    {
        return getSharesFromAssets(assets_);
    }

    /// @notice for this many shares/uniLp we need to pay at least this many assets
    /// @dev adds slippage for over-approving asset to cover possible reserves fluctuation. value is returned to the user in full
    function previewMint(uint256 shares_)
        public
        view
        override
        returns (uint256 assets)
    {
        /// NOTE: Ensure this covers liquidity requested for a block!
        assets = mintAssets(shares_);
    }

    /// @notice how many shares of this wrapper LP we need to burn to get this amount of token0 assets
    function previewWithdraw(uint256 assets_)
        public
        view
        override
        returns (uint256 shares)
    {
        return getSharesFromAssets(assets_);
    }

    function previewRedeem(uint256 shares_)
        public
        view
        override
        returns (uint256 assets)
    {
        /// NOTE: Because we add slipage for mint() here it means extra funds to redeemer.
        return redeemAssets(shares_);
    }

    /// I am burning SHARES, how much of (virtual) ASSETS (tokenX) do I get (as sum of both tokens)
    function convertToAssets(uint256 shares_)
        public
        view
        override
        returns (uint256 assets)
    {
        assets = redeemAssets(shares_);
    }

    /// @notice calculate value of shares of this vault as the sum of t0/t1 of UniV2 pair simulated as t0 or t1 total amount after swap
    /// @notice This is vulnerable to manipulation of getReserves!
    function mintAssets(uint256 shares_) public view returns (uint256 assets) {
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );
        /// shares of uni pair contract
        uint256 pairSupply = pair.totalSupply();

        /// amount of token0 to provide to receive poolLpAmount
        uint256 assets0_ = (reserveA * shares_) / pairSupply;
        uint256 a0 = assets0_ + _getSlippage(assets0_);

        /// amount of token1 to provide to receive poolLpAmount
        uint256 assets1_ = (reserveB * shares_) / pairSupply;
        uint256 a1 = assets1_ + _getSlippage(assets1_);

        if (a1 == 0 || a0 == 0) return 0;

        (reserveA, reserveB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );

        /// NOTE: Can be manipulated!
        return a0 + UniswapV2Library.getAmountOut(a1, reserveB, reserveA);
    }

    /// @notice separate from mintAssets virtual assets calculation from shares, but with omitted slippage to stop overwithdraw from Vault's balance
    function redeemAssets(uint256 shares_)
        public
        view
        returns (uint256 assets)
    {
        (uint256 a0, uint256 a1) = getAssetsAmounts(shares_);

        if (a1 == 0 || a0 == 0) return 0;

        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );

        /// NOTE: Can be manipulated!
        return a0 + UniswapV2Library.getAmountOut(a1, reserveB, reserveA);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL SWAP LOGIC FOR TOKEN X/Y
    //////////////////////////////////////////////////////////////*/

    /// @dev NOTE: Unused now, useful for on-chain oracle implemented inside of deposit/mint standard ERC4626 functions
    function _swapJoinProtected(uint256 assets_, uint256 minAmountOut_)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = _swapJoin(assets_);
        if (amount1 < minAmountOut_) revert NOT_MIN_AMOUNT_OUT();
    }

    /// @dev NOTE: Unused now, useful for on-chain oracle implemented inside of withdraw/redeem standard ERC4626 functions
    function _swapExitProtected(uint256 assets_, uint256 minAmountOut_)
        internal
        returns (uint256 amounts)
    {
        (amounts) = _swapExit(assets_);
        if (amounts < minAmountOut_) revert NOT_MIN_AMOUNT_OUT();
    }

    /// @notice directional swap from asset to opposite token (asset != tokenX)
    /// @notice calculates optimal (for the current block) amount of token0/token1 to deposit into UniswapV2Pair and splits provided assets according to the formula
    function _swapJoin(uint256 assets_)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 reserve = _getReserves();
        /// NOTE:
        /// resA if asset == token0
        /// resB if asset == token1
        uint256 amountToSwap = UniswapV2Library.getSwapAmount(reserve, assets_);

        (address fromToken, address toToken) = _getJoinToken();
        /// NOTE: amount1 == amount of token other than asset to deposit
        amount1 = DexSwap.swap(
            /// amt to swap
            amountToSwap,
            /// from asset
            fromToken,
            /// to asset
            toToken,
            /// pair address
            address(pair)
        );
        /// NOTE: amount0 == amount of underlying asset after swap to required asset
        amount0 = assets_ - amountToSwap;
    }

    /// @notice directional swap from asset to opposite token (asset != tokenX)
    /// @notice exit is in opposite direction to Join but we don't need to calculate splitting, just swap provided assets, check happens in withdraw/redeem
    function _swapExit(uint256 assets_) internal returns (uint256 amounts) {
        (address fromToken, address toToken) = _getExitToken();
        amounts = DexSwap.swap(
            /// amt to swap
            assets_,
            /// from asset
            fromToken,
            /// to asset
            toToken,
            /// pair address
            address(pair)
        );
    }

    /// @notice Sort function for this Vault Uniswap pair exit operation
    function _getExitToken() internal view returns (address t0, address t1) {
        if (token0 == asset) {
            t0 = address(token1);
            t1 = address(token0);
        } else {
            t0 = address(token0);
            t1 = address(token1);
        }
    }

    /// @notice Sort function for this Vault Uniswap pair join operation
    function _getJoinToken() internal view returns (address t0, address t1) {
        if (token0 == asset) {
            t0 = address(token0);
            t1 = address(token1);
        } else {
            t0 = address(token1);
            t1 = address(token0);
        }
    }

    /// @notice Selector for reseve of underlying asset
    function _getReserves() internal view returns (uint256 assetReserves) {
        if (token0 == asset) {
            (assetReserves, ) = UniswapV2Library.getReserves(
                address(pair),
                address(token0),
                address(token1)
            );
        } else {
            (, assetReserves) = UniswapV2Library.getReserves(
                address(pair),
                address(token0),
                address(token1)
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                       UNISWAP PAIR CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice for requested 100 UniLp tokens, how much tok0/1 we need to give?
    function getAssetsAmounts(uint256 poolLpAmount_)
        public
        view
        returns (uint256 assets0, uint256 assets1)
    {
        /// get xy=k here, where x=ra0,y=ra1
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );
        /// shares of uni pair contract
        uint256 pairSupply = pair.totalSupply();

        /// amount of token0 to provide to receive poolLpAmount
        assets0 = (reserveA * poolLpAmount_) / pairSupply;

        /// amount of token1 to provide to receive poolLpAmount
        assets1 = (reserveB * poolLpAmount_) / pairSupply;
    }

    /// @notice Take amount of token0 > split to token0/token1 amounts > calculate how much shares to burn
    function getSharesFromAssets(uint256 assets_)
        public
        view
        returns (uint256 poolLpAmount)
    {
        (uint256 assets0, uint256 assets1) = getSplitAssetAmounts(assets_);

        poolLpAmount = getLiquidityAmountOutFor(assets0, assets1);
    }

    /// @notice Take amount of token0 (underlying) > split to token0/token1 (virtual) amounts
    function getSplitAssetAmounts(uint256 assets_)
        public
        view
        returns (uint256 assets0, uint256 assets1)
    {
        (uint256 resA, uint256 resB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );

        uint256 toSwapForUnderlying = UniswapV2Library.getSwapAmount(
            _getReserves(), /// either resA or resB
            assets_
        );

        if (token0 == asset) {
            /// @dev we use getMountOut because it includes 0.3 fee
            uint256 resultOfSwap = UniswapV2Library.getAmountOut(
                toSwapForUnderlying,
                resA,
                resB
            );

            assets0 = assets_ - toSwapForUnderlying;
            assets1 = resultOfSwap;
        } else {
            uint256 resultOfSwap = UniswapV2Library.getAmountOut(
                toSwapForUnderlying,
                resB,
                resA
            );

            assets0 = resultOfSwap;
            assets1 = assets_ - toSwapForUnderlying;
        }
    }

    /// @notice Calculate amount of UniswapV2Pair lp-token you will get for supply X & Y amount of token0/token1
    function getLiquidityAmountOutFor(uint256 assets0_, uint256 assets1_)
        public
        view
        returns (uint256 poolLpAmount)
    {
        uint256 pairSupply = pair.totalSupply();

        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );
        poolLpAmount = min(
            ((assets0_ * pairSupply) / reserveA),
            (assets1_ * pairSupply) / reserveB
        );
    }

    /*//////////////////////////////////////////////////////////////
                              MISC
    //////////////////////////////////////////////////////////////*/

    function _getSlippage(uint256 amount_) internal view returns (uint256) {
        return (amount_ * fee) / slippageFloat;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }
}
