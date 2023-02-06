// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "../interfaces/IUniswapV2Router.sol";
import {UniswapV2Library} from "../utils/UniswapV2Library.sol";

import {IUniswapV3Pool} from "../interfaces/IUniswapV3.sol";

import {DexSwap} from "../utils/swapUtils.sol";

import "forge-std/console.sol";

/// @notice WIP: ERC4626 UniswapV2 Adapter - Allows exit & join to UniswapV2 LP Pools from ERC4626 interface
/// Uses virtual price to calculate exit/entry amounts, which is vulnerable to pool reserve manipulation without usage of protected functions
/// Example Pool: https://v2.info.uniswap.org/pair/0xae461ca67b15dc8dc81ce7615e0320da1a9ab8d5 (DAI-USDC LP/PAIR on ETH)
contract UniswapV2ERC4626Swap is ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public immutable manager;

    /// NOTE: Hardcoded workaround to ensure execution within changing pair reserves - 0.4% (4000/1000000)
    uint256 public fee = 4000;
    uint256 public immutable slippageFloat = 1000000;

    IUniswapV2Pair public immutable pair;
    IUniswapV2Router public immutable router;
    IUniswapV3Pool public immutable oracle;

    ERC20 public token0;
    ERC20 public token1;

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

        /// TODO: Approve management
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        ERC20(address(pair)).approve(address(router), type(uint256).max);
    }

    function liquidityRemove(uint256, uint256 shares)
        internal
        returns (uint256 assets0, uint256 assets1)
    {
        /// @dev Values are sorted because we sort if t0/t1 == asset at runtime
        (assets0, assets1) = getAssetsAmounts(shares);

        /// temp implementation, we should call directly on a pair
        (assets0, assets1) = router.removeLiquidity(
            address(token0),
            address(token1),
            shares,
            assets0 - getSlippage(assets0), /// NOTE: No MEV protection, only ensuring execution within certain range to avoid reverts
            assets1 - getSlippage(assets1), /// NOTE: No MEV protection, only ensuring execution within certain range to avoid reverts
            address(this),
            block.timestamp + 100
        );
    }

    function liquidityAdd(uint256 assets0, uint256 assets1)
        internal
        returns (uint256 li)
    {
        /// temp implementation, we should call directly on a pair
        (, , li) = router.addLiquidity(
            address(token0),
            address(token1),
            assets0,
            assets1,
            assets0 - getSlippage(assets0), /// NOTE: No MEV protection, only ensuring execution within certain range to avoid reverts
            assets1 - getSlippage(assets1), /// NOTE: No MEV protection, only ensuring execution within certain range to avoid reverts
            address(this),
            block.timestamp + 100
        );
    }

    /// @notice deposit function taking additional protection parameters for execution
    /// Caller can calculate minSharesOut using previewDeposit function range of outputs
    /// Caller can calculate minSwapOut using UniswapV2Library.getAmountOut range of outputs
    function deposit(
        uint256 assets,
        address receiver,
        uint256 minSharesOut /// @dev calculated off-chain, "secure" deposit function. could be using tick-like calculations?
    ) public returns (uint256 shares) {
        asset.safeTransferFrom(msg.sender, address(this), assets);

        /// @dev caller calculates minSwapOut from uniswapV2Library off-chain, reverts if swap is manipulated
        /// TODO: Is minSwapOut needed if we already have minSharesOut?
        (uint256 a0, uint256 a1) = swapJoin(assets);

        shares = liquidityAdd(a0, a1);

        /// @dev caller calculates minSharesOut off-chain, this contracts functions can be used to retrive reserves over the past blocks
        require(shares >= minSharesOut, "UniswapV2ERC4626Swap: minSharesOut");

        /// @dev we just pass uniswap lp-token amount to user
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice receives tokenX of UniV2 pair and mints shares of this vault for deposited tokenX/Y into UniV2 pair
    /// @dev unsecure deposit function, trusting external asset reserves
    /// NOTE: At this point, what good does it to have strict ERC4626 deposit if its so prone to manipulation?
    /// @notice Caller can calculate shares through previewDeposit and trust previewDeposit returned value to revert here
    /// any minSharesOut check should be performed by the caller and his contract (TODO: Can we provide low/high bounds for shares?)
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        /// @dev can be manipulated before making deposit() call
        /// NOTE: Re-think if calling this after swapJoin() and liquidityAdd() is better
        /// NOTE: What if we would call two times and check delta between outputs? May be just another weak validation
        shares = previewDeposit(assets);

        /// @dev 100% of tokenX/Y is transferred to this contract
        asset.safeTransferFrom(msg.sender, address(this), assets);

        /// @dev swap from 100% to ~50% of tokenX/Y
        /// NOTE: Can be manipulated if caller manipulated reserves before deposit() call
        /// NOTE: Is there a risk in inflating this swapJoin() call? It will generate fees for holders of shares
        (uint256 a0, uint256 a1) = swapJoin(assets);

        /// NOTE: Pool reserve could be manipulated
        /// NOTE: reserve manipulation, leading to inflation of shares is meaningless, because redemption happens against UniV2Pair not this Vault balance
        uint256 uniShares = liquidityAdd(a0, a1);

        /// @dev totalAssets holds sum of all UniLP,
        /// NOTE: UniLP is non-rebasing, yield accrues on Uniswap pool (you can redeem more t0/t1 for same amount of LP)
        /// NOTE: If we want it as Strategy, e.g do something with this LP, then we need to calculate shares, 1:1 won't work
        /// NOTE: Caller needs to trust previewDeposit return value which can be manipulated for 1 block
        require((uniShares >= shares), "SHARES_AMOUNT_OUT");

        /// @dev we want to have 1:1 relation to UniV2Pair lp token
        shares = uniShares;

        /// NOTE: TBD: oracle or smth else
        // (uint256 lowBound, uint256 highBound) = getAvgPriceBound();
        // require((uniShares >= lowBound && uniShares <= highBound), "SHARES_AMOUNT_OUT");

        _mint(receiver, uniShares);

        emit Deposit(msg.sender, receiver, assets, uniShares);
    }

    function mint(uint256 shares, address receiver, uint256 minSharesOut) public returns (uint256 assets) {
        assets = previewMint(shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        (uint256 a0, uint256 a1) = swapJoin(assets);

        uint256 uniShares = liquidityAdd(a0, a1);

        /// @dev Protected mint, caller can calculate minSharesOut off-chain
        require((uniShares >= minSharesOut), "SHARES_AMOUNT_OUT");

        _mint(receiver, uniShares);

        emit Deposit(msg.sender, receiver, assets, uniShares);    }

    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {
        assets = previewMint(shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        (uint256 a0, uint256 a1) = swapJoin(assets);

        /// TODO: Same checks as in deposit
        uint256 uniShares = liquidityAdd(a0, a1);
        console.log("uniShares", uniShares);
        console.log("shares", shares);

        /// NOTE: PreviewMint needs to output reasonable amount of shares
        require((uniShares >= shares), "SHARES_AMOUNT_OUT");

        _mint(receiver, uniShares);

        emit Deposit(msg.sender, receiver, assets, uniShares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 minAmountOut /// @dev calculated off-chain, "secure" withdraw function.
    ) public returns (uint256 shares) {
        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        (uint256 assets0, uint256 assets1) = liquidityRemove(assets, shares);

        _burn(owner, shares);

        uint256 amount = asset == token0
            ? swapExit(assets1) + assets0
            : swapExit(assets0) + assets1;

        console.log("amount", amount, "assets", assets);

        /// @dev Protected amount out check
        require(amount >= minAmountOut, "ASSETS_AMOUNT_OUT");

        asset.safeTransfer(receiver, amount);

        emit Withdraw(msg.sender, receiver, owner, amount, shares);        
    }

    /// @notice burns shares from owner and sends exactly assets of underlying tokens to receiver.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        (uint256 assets0, uint256 assets1) = liquidityRemove(assets, shares);

        _burn(owner, shares);

        /// @dev ideally contract for token0/1 should know what assets amount to use without conditional checks, gas overhead
        uint256 amount = asset == token0
            ? swapExit(assets1) + assets0
            : swapExit(assets0) + assets1;

        console.log("amount", amount, "assets", assets);

        /// NOTE: This is a weak check anyways. previews can be manipulated.
        /// NOTE: If enabled, withdraws() which didn't accrue enough of the yield to cover deposit's swapJoin() will fail
        /// NOTE: For secure execution user should use protected functions
        // require(amount >= assets, "ASSETS_AMOUNT_OUT");

        asset.safeTransfer(receiver, amount);

        emit Withdraw(msg.sender, receiver, owner, amount, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minAmountOut /// @dev calculated off-chain, "secure" withdraw function.
    ) public returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        (uint256 assets0, uint256 assets1) = liquidityRemove(assets, shares);

        _burn(owner, shares);

        uint256 amount = asset == token0
            ? swapExit(assets1) + assets0
            : swapExit(assets0) + assets1;

        /// @dev Protected amount check
        require(amount >= minAmountOut, "ASSETS_AMOUNT_OUT");

        asset.safeTransfer(receiver, amount);

        emit Withdraw(msg.sender, receiver, owner, amount, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        (uint256 assets0, uint256 assets1) = liquidityRemove(assets, shares);

        _burn(owner, shares);

        /// @dev ideally contract for token0/1 should know what assets amount to use without conditional checks, gas overhead
        uint256 amount = asset == token0
            ? swapExit(assets1) + assets0
            : swapExit(assets0) + assets1;

        /// NOTE: See note in withdraw()
        // console.log("amount", amount, "assets", assets);
        // require(amount >= assets, "ASSETS_AMOUNT_OUT");

        asset.safeTransfer(receiver, amount);

        emit Withdraw(msg.sender, receiver, owner, amount, shares);
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////// ACCOUNTING //////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    /// @notice totalAssets is equal to UniswapV2Pair lp tokens minted through this adapter
    function totalAssets() public view override returns (uint256) {
        return pair.balanceOf(address(this));
    }

    /// @notice for this many asset (ie token0) we get this many shares
    function previewDeposit(uint256 assets)
        public
        view
        override
        returns (uint256 shares)
    {
        return getSharesFromAssets(assets);
    }

    /// @notice for this many shares/uniLp we need to pay at least this many assets
    /// @dev adds slippage for over-approving asset to cover possible reserves fluctuation. value is returned to the user in full
    function previewMint(uint256 shares)
        public
        view
        override
        returns (uint256 assets)
    {
        /// NOTE: Ensure this covers liquidity requested for a block!
        assets = mintAssets(shares);
    }

    /// @notice how many shares of this wrapper LP we need to burn to get this amount of token0 assets
    function previewWithdraw(uint256 assets)
        public
        view
        override
        returns (uint256 shares)
    {
        return getSharesFromAssets(assets);
    }

    function previewRedeem(uint256 shares)
        public
        view
        override
        returns (uint256 assets)
    {
        /// NOTE: Because we add slipage for mint() here it means extra funds to redeemer.
        return redeemAssets(shares);
    }

    /// I am burning SHARES, how much of (virtual) ASSETS (tokenX) do I get (as sum of both tokens)
    function convertToAssets(uint256 shares)
        public
        view
        override
        returns (uint256 assets)
    {
        assets = redeemAssets(shares);
    }

    /// @notice calculate value of shares of this vault as the sum of t0/t1 of UniV2 pair simulated as t0 or t1 total amount after swap
    /// NOTE: This is vulnerable to manipulation of getReserves!
    function mintAssets(uint256 shares) public view returns (uint256 assets) {
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );
        /// shares of uni pair contract
        uint256 pairSupply = pair.totalSupply();

        /// amount of token0 to provide to receive poolLpAmount
        uint256 assets0_ = (reserveA * shares) / pairSupply;
        uint256 a0 = assets0_ + getSlippage(assets0_);
        // console.log("assets0", assets0, "assets0_", assets0_);

        /// amount of token1 to provide to receive poolLpAmount
        uint256 assets1_ = (reserveB * shares) / pairSupply;
        uint256 a1 = assets1_ + getSlippage(assets1_);
        // console.log("assets1", assets1, "assets1_", assets1_);

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
    function redeemAssets(uint256 shares) public view returns (uint256 assets) {
        (uint256 a0, uint256 a1) = getAssetsAmounts(shares);

        if (a1 == 0 || a0 == 0) return 0;

        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );

        /// NOTE: Can be manipulated!
        return a0 + UniswapV2Library.getAmountOut(a1, reserveB, reserveA);
    }

    ////////////////////////////////////////////////////////////////////////////
    /////////////////////////// UNISWAP CALLS //////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    /// @dev TODO: Unused now, useful for on-chain oracle implemented inside of deposit/mint standard ERC4626 functions
    function swapJoinProtected(uint256 assets, uint256 minAmountOut)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = swapJoin(assets);
        require(amount1 >= minAmountOut, "amount1 < minAmountOut");
    }

    /// @dev TODO: Unused now, useful for on-chain oracle implemented inside of withdraw/redeem standard ERC4626 functions
    function swapExitProtected(uint256 assets, uint256 minAmountOut)
        internal
        returns (uint256 amounts)
    {
        (amounts) = swapExit(assets);
        require(amounts >= minAmountOut, "amounts < minAmountOut");
    }

    /// @notice directional swap from asset to opposite token (asset != tokenX) TODO: consolidate Join/Exit
    /// calculates optimal (for the current block) amount of token0/token1 to deposit into UniswapV2Pair and splits provided assets according to the formula
    function swapJoin(uint256 assets)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 reserve = _getReserves();
        /// NOTE:
        /// resA if asset == token0
        /// resB if asset == token1
        uint256 amountToSwap = UniswapV2Library.getSwapAmount(reserve, assets);

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
        amount0 = assets - amountToSwap;
    }

    /// @notice directional swap from asset to opposite token (asset != tokenX) TODO: consolidate Join/Exit
    /// exit is in opposite direction to Join but we don't need to calculate splitting, just swap provided assets, check happens in withdraw/redeem
    function swapExit(uint256 assets) internal returns (uint256 amounts) {
        (address fromToken, address toToken) = _getExitToken();
        amounts = DexSwap.swap(
            /// amt to swap
            assets,
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

    /// @notice for requested 100 UniLp tokens, how much tok0/1 we need to give?
    function getAssetsAmounts(uint256 poolLpAmount)
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
        assets0 = (reserveA * poolLpAmount) / pairSupply;

        /// amount of token1 to provide to receive poolLpAmount
        assets1 = (reserveB * poolLpAmount) / pairSupply;
    }

    /// @notice Take amount of token0 > split to token0/token1 amounts > calculate how much shares to burn
    function getSharesFromAssets(uint256 assets)
        public
        view
        returns (uint256 poolLpAmount)
    {
        (uint256 assets0, uint256 assets1) = getSplitAssetAmounts(assets);

        poolLpAmount = getLiquidityAmountOutFor(assets0, assets1);
    }

    /// @notice Take amount of token0 (underlying) > split to token0/token1 (virtual) amounts
    function getSplitAssetAmounts(uint256 assets)
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
            assets
        );

        if (token0 == asset) {
            /// @dev we use getMountOut because it includes 0.3 fee
            uint256 resultOfSwap = UniswapV2Library.getAmountOut(
                toSwapForUnderlying,
                resA,
                resB
            );

            assets0 = assets - toSwapForUnderlying;
            assets1 = resultOfSwap;
        } else {
            uint256 resultOfSwap = UniswapV2Library.getAmountOut(
                toSwapForUnderlying,
                resB,
                resA
            );

            assets0 = resultOfSwap;
            assets1 = assets - toSwapForUnderlying;
        }
    }

    function getLiquidityAmountOutFor(uint256 assets0, uint256 assets1)
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
            ((assets0 * pairSupply) / reserveA),
            (assets1 * pairSupply) / reserveB
        );
    }

    ////////////////////////////////////////////////////////////////////////////
    /////////////////////////// SLIPPAGE MGMT //////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    function getSlippage(uint256 amount) internal view returns (uint256) {
        return (amount * fee) / slippageFloat;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }
}
