// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "../interfaces/IUniswapV2Router.sol";
import {UniswapV2Library} from "../utils/UniswapV2Library.sol";

import {DexSwap} from "../utils/swapUtils.sol";

import "forge-std/console.sol";

/// @notice Custom ERC4626 Wrapper for UniV2 Pools with built-in swap
/// https://v2.info.uniswap.org/pair/0xae461ca67b15dc8dc81ce7615e0320da1a9ab8d5 (DAI-USDC LP/PAIR on ETH)
contract UniswapV2WrapperERC4626Swap is ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public immutable manager;

    uint256 public slippage;
    uint256 public immutable slippageFloat = 10000;

    IUniswapV2Pair public immutable pair;
    IUniswapV2Router public immutable router;

    /// For simplicity, we use solmate's ERC20 interface
    ERC20 public token0;
    ERC20 public token1;

    constructor(
        ERC20 tokenX,
        string memory name_,
        string memory symbol_,
        IUniswapV2Router router_,
        IUniswapV2Pair pair_,
        uint256 slippage_
    ) ERC4626(tokenX, name_, symbol_) {
        manager = msg.sender;

        pair = pair_;
        router = router_;

        /// TODO: Factory deployment + init pattern to cover token0/token1 instantly
        token0 = ERC20(pair.token0());
        token1 = ERC20(pair.token1());

        slippage = slippage_;

        /// Approve management TODO
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        asset.approve(address(router), type(uint256).max);
    }

    function beforeWithdraw(uint256 assets, uint256 shares) internal override {
        /// now we have DAI virtual amount here passed
        /// lets say user wants 80 DAI out of 100 DAI deposit
        /// get a0,a1, if a0 = assets > removeLiquidity > send a0
        /// TODO: WARN: call swap again with remaining a1

        /// this makes APY on this Vault volatile (each exit from vault makes non-optimal swaps, 0.3% fee eaten)
        (uint256 assets0, uint256 assets1) = getAssetsAmounts(shares);
    
        console.log("totalAssets", totalAssets());
        console.log("withdraw shares", shares);
        console.log("withdraw a0", assets0, "a1", assets1);
        uint slip1 = getSlippage(assets0);
        uint slip2 = getSlippage(assets1);
        console.log("s1", slip1, "s2", slip2);

        /// temp implementation, we should call directly on a pair
        (uint256 aA, uint256 aB) = router.removeLiquidity(
            address(token0),
            address(token1),
            shares,
            assets0 - getSlippage(assets0),
            assets1 - getSlippage(assets1),
            address(this),
            block.timestamp + 100
        );

        // if (aA <= assets) {

        // }

        /// TODO: Re-deposit mechanism

        console.log("aA", aA, "aB", aB);
    }

    function liquidityDeposit() internal returns (uint256 li) {
        (uint256 assets0, uint256 assets1) = getAssetBalance();

        /// temp implementation, we should call directly on a pair
        (, , li) = router.addLiquidity(
            address(token0),
            address(token1),
            assets0,
            assets1,
            assets0 - getSlippage(assets0),
            assets1 - getSlippage(assets1),
            address(this),
            block.timestamp + 100
        );
    }

    /// User gives N amount of an underlying asset (DAI)
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {

        asset.safeTransferFrom(msg.sender, address(this), assets);

        swap(assets);

        /// @dev totalAssets holds sum of all UniLP, 
        /// UniLP is non-rebasing, yield accrues on Uniswap pool (you can redeem more t0/t1 for same amount of LP)
        require((shares = liquidityDeposit()) != 0, "ZERO_SHARES");

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {
        /// TODO To implement previewMint calculations
        assets = previewMint(shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        swap(assets);

        liquidityDeposit();

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @dev burns shares from owner and sends exactly assets of underlying tokens to receiver.
    function withdraw(
        uint256 assets, /// token0 amount (we need to get it from token0 & token1 in LP)
        address receiver,
        address owner
    ) public override returns (uint256 shares) {

        /// how many shares of this wrapper LP we need to burn to get this amount of token0 assets
        /// If user joined with 100 DAI, he owns a claim to 50token0/50token1
        /// this will output required shares to burn for only token0
        /// should we simulate full split here?
        shares = previewWithdraw(assets);
        console.log("shares to burn for asset", shares);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        console.log("assets safeTransfer", assets);
        
        /// TODO: We need to account for token1 amounts
        token0.safeTransfer(receiver, assets);
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

        console.log("redeem assets", assets);

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        /// TODO
        token0.safeTransfer(receiver, assets);
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////// ACCOUNTING //////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    /// totalAssets virtualAssets should grow with fees accrued to lp tokens held by this vault
    function totalAssets() public view override returns (uint256) {
        return pairBalance();
    }

    function pairBalance() public view returns (uint256) {
        return pair.balanceOf(address(this));
    }

    function virtualAssets(uint256 shares) public view returns (uint256 assets) {
        (uint256 a0, uint256 a1) = getAssetsAmounts(shares);

        if (a1 == 0) return 0;
        
        (uint256 resA, uint256 resB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );

        /// DAI + DAI amt from USDC swapped to DAI
        return a0 + UniswapV2Library.getAmountOut(a1, resB, resA);
    }

    /// for this many DAI (assets) we get this many shares
    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        (uint256 resA, uint256 resB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );

        uint256 swapAmt = UniswapV2Library.getSwapAmount(resA, assets);

        shares = getLiquidityAmountOutFor(assets, swapAmt);
    }

    /// we need only assets umount up to the 50% LP amount
    /// how many shares of this wrapper LP we need to burn to get this amount of token0 assets
    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        return getSharesFromAssets(assets);
    }


    ////////////////////////////////////////////////////////////////////////////
    /////////////////////////// UNISWAP CALLS //////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    function swap(uint256 assets) internal returns (uint256 swapAmt) {
        (uint256 resA, uint256 resB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );

        swapAmt = UniswapV2Library.getSwapAmount(resA, assets);

        DexSwap.swap(
            /// amt to swap
            swapAmt,
            /// from asset (DAI)
            pair.token0(),
            /// to asset (USDC)
            pair.token1(),
            /// pair address
            address(pair)
        );
    }

    function getAssetBalance() internal view returns (uint256 a0, uint256 a1) {
        a0 = token0.balanceOf(address(this));
        a1 = token1.balanceOf(address(this));
    }

    /// For requested 100 UniLp tokens, how much tok0/1 we need to give?
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

    /// @notice Take amount of token0 > split to token0/token1 amounts > calculate how much shares to burn
    function getSharesFromAssets(uint256 assets) public view returns (uint256 poolLpAmount) {

        (uint256 resA, uint256 resB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );

        uint256 amountOfDaiToSwapToUSDC = UniswapV2Library.getSwapAmount(resA, assets);
        uint256 amountOfUSDCfromDAI = UniswapV2Library.quote(amountOfDaiToSwapToUSDC, resA, resB);
        
        console.log("amountOfDaiToSwapToUSDC", amountOfDaiToSwapToUSDC);
        console.log("amountOfUSDCfromDAI", amountOfUSDCfromDAI);

        poolLpAmount = getLiquidityAmountOutFor(amountOfDaiToSwapToUSDC, amountOfUSDCfromDAI);
    }

    ////////////////////////////////////////////////////////////////////////////
    /////////////////////////// SLIPPAGE MGMT //////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    function setSlippage(uint256 amount) external {
        require(msg.sender == manager, "owner");
        require(amount < 10000 && amount > 9000); /// 10% max slippage
        slippage = amount;
    }

    function getSlippage(uint256 amount) internal view returns (uint256) {
        return (amount * slippage) / slippageFloat;
    }


    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

}
