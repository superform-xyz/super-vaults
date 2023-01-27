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
/// Uses virtual price to calculate exit/entry amounts - WHICH IS CURRENTLY FULLY EXPOSED TO ON-CHAIN MANIPULATION :)
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

    function liquidityRemove(uint256 assets, uint256 shares)
        internal
        returns (uint256 assets0, uint256 assets1)
    {
        /// now we have asset (t0 || t1) virtual amount passed as arg
        /// TODO: use this amount for allowed slippage checks (for simulated output vs real removeLiquidity t0/t1)

        /// @dev Values are sorted because we sort if t0/t1 == asset at runtime
        (assets0, assets1) = getAssetsAmounts(shares);

        /// temp implementation, we should call directly on a pair
        (assets0, assets1) = router.removeLiquidity(
            address(token0),
            address(token1),
            shares,
            assets0 - getSlippage(assets0), /// NOTE: This offers no protection. whole amt needs to verified by external oracle
            assets1 - getSlippage(assets1), /// NOTE: This offers no protection. whole amt needs to verified by external oracle
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
            assets0 - getSlippage(assets0), /// NOTE: This offers no protection. whole amt needs to verified by external oracle
            assets1 - getSlippage(assets1), /// NOTE: This offers no protection. whole amt needs to verified by external oracle
            address(this),
            block.timestamp + 100
        );
    }

    /// @notice deposit function taking additional protection parameters for execution
    function deposit(
        uint256 assets,
        address receiver,
        uint256 minSharesOut, /// @dev calculated off-chain, "secure" deposit function. could be using tick-like calculations?
        uint256 minSwapOut /// @dev calculated off-chain, "secure" deposit function. 
    ) public returns (uint256 shares) {
        require((shares = previewDeposit(assets)) >= minSharesOut, "UniswapV2ERC4626Swap: minSharesOut");

        asset.safeTransferFrom(msg.sender, address(this), assets);

        (uint256 a0, uint256 a1) = swapJoinProtected(assets, minSwapOut);

        uint256 uniShares = liquidityAdd(a0, a1);
        
        require(uniShares >= minSharesOut, "UniswapV2ERC4626Swap: minSharesOut");

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
        // shares = previewDeposit(assets);

        /// 100% of tokenX/Y is transferred to this contract
        asset.safeTransferFrom(msg.sender, address(this), assets);

        /// swap from 100% to ~50% of tokenX/Y
        /// NOTE: Can be manipulated if caller manipulated reserves before deposit() call
        (uint256 a0, uint256 a1) = swapJoin(assets); /// NOTE: Secure swap by minAmountOut from Oracle

        /// NOTE: Pool reserve could be manipulated
        /// @dev What severity? It seems that attacker wouldn't gain anything because we operate on 1:1 uniShares : shares
        uint256 uniShares = liquidityAdd(a0, a1);

        /// @dev totalAssets holds sum of all UniLP,
        /// UniLP is non-rebasing, yield accrues on Uniswap pool (you can redeem more t0/t1 for same amount of LP)
        /// NOTE: If we want it as Strategy, e.g do something with this LP, then we need to calculate shares, 1:1 won't work
        /// NOTE: If we already trust previewDeposit, swapJoin is secured?
        require((uniShares >= (shares = previewDeposit(assets))), "SHARES_AMOUNT_OUT"); /// NOTE: reserve manipulation in context of LP seems not to lead to value loss for user?

        // (uint256 lowBound, uint256 highBound) = getAvgPriceBound();
        // require((uniShares >= lowBound && uniShares <= highBound), "SHARES_AMOUNT_OUT");
        
        /// NOTE: Users may be leaving some shares unasigned on Vault balance
        _mint(receiver, uniShares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {
        assets = previewMint(shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        (uint256 a0, uint256 a1) = swapJoin(assets);

        /// TODO Same checks as in deposit
        uint256 uniShares = liquidityAdd(a0, a1);
        console.log("uniShares", uniShares);
        console.log("shares", shares);

        /// NOTE: PreviewMint needs to output reasonable
        require((uniShares >= shares), "SHARES_AMOUNT_OUT");

        _mint(receiver, uniShares);

        emit Deposit(msg.sender, receiver, assets, shares);
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

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        /// @dev ideally contract for token0/1 should know what assets amount to use without conditional checks, gas overhead
        uint256 amount = asset == token0
            ? swapExit(assets1) + assets0
            : swapExit(assets0) + assets1;

        asset.safeTransfer(receiver, amount);
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

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        /// @dev ideally contract for token0/1 should know what assets amount to use without conditional checks, gas overhead
        uint256 amount = asset == token0
            ? swapExit(assets1) + assets0
            : swapExit(assets0) + assets1;

        asset.safeTransfer(receiver, amount);
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////// ACCOUNTING //////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    /// @notice totalAssets virtualAssets should grow with fees accrued to lp tokens held by this vault
    function totalAssets() public view override returns (uint256) {
        return pair.balanceOf(address(this));
    }

    /// @notice for this many DAI (assets) we get this many shares
    function previewDeposit(uint256 assets)
        public
        view
        override
        returns (uint256 shares)
    {
        return getSharesFromAssets(assets);
    }

    /// @notice for this many shares/uniLp we need to pay at least this many assets
    /// @dev adds slippage for overapproval to cover eventual reserve fluctuation, value is returned to user in full
    function previewMint(uint256 shares)
        public
        view
        override
        returns (uint256 assets)
    {
        /// NOTE: Ensure this covers liquidity requested for a block!
        assets = mintAssets(shares);
    }

    /// we need only assets umount up to the 50% LP amount
    /// how many shares of this wrapper LP we need to burn to get this amount of token0 assets
    function previewWithdraw(uint256 assets)
        public
        view
        override
        returns (uint256 shares)
    {
        return getSharesFromAssets(assets);
    }

    /// @notice TODO: Currently unused, only to simulate value. Adding slipage makes this usefull.
    function previewRedeem(uint256 shares)
        public
        view
        override
        returns (uint256 assets)
    {
        /// NOTE: Because we add slipage for mint() here it means extra funds to redeemer, needs separate virtualAssets() than mint()
        return redeemAssets(shares);
    }

    /// I am burning SHARES, how much of (virtual) ASSETS (tokenX) do I get (in sum of both tokens)
    function convertToAssets(uint256 shares)
        public
        view
        override
        returns (uint256 assets)
    {
        assets = redeemAssets(shares);
    }

    /// @notice calculate value of shares of this vault as the sum of t0/t1 of UniV2 pair simulated as t0 or t1 total amount after swap
    /// NOTE: This is vulnerable to manipulation of getReserves! TODO: Add on-chain oracle checks
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

        (uint256 resA, uint256 resB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );

        // NOTE: VULNERABLE!
        return a0 + UniswapV2Library.getAmountOut(a1, resB, resA);
    }

    /// @notice separate from mintAssets virtual assets calculation from shares, but with omitted slippage to stop overwithdraw from Vault's balance
    function redeemAssets(uint256 shares) public view returns (uint256 assets) {
        /// get xy=k here, where x=ra0,y=ra1
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );

        /// shares of uni pair contract
        uint256 pairSupply = pair.totalSupply();
        /// amount of token0 to provide to receive poolLpAmount
        uint256 a0 = (reserveA * shares) / pairSupply;
        /// amount of token1 to provide to receive poolLpAmount
        uint256 a1 = (reserveB * shares) / pairSupply;

        if (a1 == 0 || a0 == 0) return 0;

        (uint256 resA, uint256 resB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );

        // NOTE: VULNERABLE!
        return a0 + UniswapV2Library.getAmountOut(a1, resB, resA);
    }

    ////////////////////////////////////////////////////////////////////////////
    /////////////////////////// UNISWAP CALLS //////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    function swapJoinProtected(uint256 assets, uint256 minAmountOut) internal returns (uint256 amount0, uint256 amount1) {
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
    /// calculates optimal (for current block) amount of token0/token1 to deposit to Uni Pool and splits provided assets according to formula
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

    function getAssetBalance() internal view returns (uint256 a0, uint256 a1) {
        a0 = token0.balanceOf(address(this));
        a1 = token1.balanceOf(address(this));
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
            uint256 resultOfSwap = UniswapV2Library.getAmountOut(
                toSwapForUnderlying,
                resA,
                resB
            );

            assets0 = toSwapForUnderlying;
            assets1 = resultOfSwap;
        } else {
            uint256 resultOfSwap = UniswapV2Library.getAmountOut(
                toSwapForUnderlying,
                resB,
                resA
            );

            assets0 = resultOfSwap;
            assets1 = toSwapForUnderlying;
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

    function getOraclePrice() public view returns (int56[] memory) {
        uint32[] memory secondsAgo = new uint32[](1);
        secondsAgo[0] = 1;
        (int56[] memory prices, ) = oracle.observe(secondsAgo);
        return prices;
    }

    function getSafeExchangeRate(uint256 v2amount)
        public
        view
        returns (uint256 diff)
    {}

    ////////////////////////////////////////////////////////////////////////////
    /////////////////////////// SLIPPAGE MGMT //////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    /// NOTE: Unwanted behavior of double counting fee because of the twap implementation
    function getSlippage(uint256 amount) internal view returns (uint256) {
        return (amount * fee) / slippageFloat;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }
}
