// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IUniswapV2ERC20} from "./interfaces/IUniswapV2ERC20.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "./interfaces/IUniswapV2Router.sol";
import {UniswapV2Library} from "./utils/UniswapV2Library.sol";

import "forge-std/console.sol";

// Vault (ERC4626) - totalAssets() == lpToken of Uniswap Pool
// deposit(assets) -> assets could be lpToken number? then we make previews clever
// - user needs to approve both A,B tokens in X,Y amounts
// - deposit() safeTransfersFrom A,B
// - checks are run against expected lpTokens amounts from Uniswap && || lpTokens already at balance
// withdraw() -> withdraws both A,B in accrued X+n,Y+n amounts

/// https://v2.info.uniswap.org/pair/0xae461ca67b15dc8dc81ce7615e0320da1a9ab8d5 (DAI-USDC LP/PAIR on ETH)
contract UniswapV2WrapperERC4626 is ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public immutable manager;

    IUniswapV2Pair public immutable pair;
    IUniswapV2Router public immutable router;

    /// For simplicity, we use solmate's ERC20 interface
    ERC20 public token0;
    ERC20 public token1;

    constructor(
        string memory name_,
        string memory symbol_,
        ERC20 asset_, /// Pair address
        ERC20 token0_,
        ERC20 token1_,
        IUniswapV2Router router_,
        IUniswapV2Pair pair_ /// Pair address
    ) ERC4626(asset_, name_, symbol_) {
        manager = msg.sender;
        pair = pair_;
        router = router_;
        token0 = token0_;
        token1 = token1_;
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        asset.approve(address(router), type(uint256).max);
    }

    function beforeWithdraw(uint256 assets, uint256 shares) internal override {
        (uint256 assets0, uint256 assets1) = getAssetsAmounts(assets);

        /// temp implementation, we should call directly on a pair
        router.removeLiquidity(
            address(token0),
            address(token1),
            assets,
            assets0 - 1000,
            assets1 - 1000,
            address(this),
            block.timestamp + 100
        );
    }

    function afterDeposit(uint256 assets, uint256 shares) internal override {
        (uint256 assets0, uint256 assets1) = getAssetsAmounts(assets);

        /// temp implementation, we should call directly on a pair
        router.addLiquidity(
            address(token0),
            address(token1),
            assets0,
            assets1,
            assets0 - 1,
            assets1 - 1,
            address(this),
            block.timestamp + 100
        );
    }

    /// User wants to get 100 UniLP (underlying)
    /// REQUIREMENT: Calculate amount of assets and have enough of assets0/1 to cover this amount for LP requested (slippage!)
    /// @param assets == Assume caller called previewDeposit() first for calc on amount of assets to give approve to
    /// assets value == amount of lpToken to mint (asset) from token0 & token1 input (function has no knowledge of inputs)
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        /// From 100 uniLP msg.sender gets N shares (of this Vault)
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        /// Ideally, msg.sender should call this function beforehand to get correct "assets" amount
        (uint256 assets0, uint256 assets1) = getAssetsAmounts(assets);

        token0.safeTransferFrom(msg.sender, address(this), assets0);

        token1.safeTransferFrom(msg.sender, address(this), assets1);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    /// User want to get 100 VaultLP (vault's token) worth N UniLP
    /// shares value == amount of Vault token (shares) to mint from requested lpToken
    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {
        (uint256 assets0, uint256 assets1) = getAssetsAmounts(assets);

        token0.safeTransferFrom(msg.sender, address(this), assets0);

        token1.safeTransferFrom(msg.sender, address(this), assets1);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    /// User wants to burn 100 UniLP (underlying) for N worth of token0/1
    function withdraw(
        uint256 assets, // amount of underlying asset (pool Lp) to withdraw
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets);
        console.log("shares", shares);

        (uint256 assets0, uint256 assets1) = getAssetsAmounts(assets);
        console.log("a0", assets0, "a1", assets1);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        token0.safeTransfer(receiver, assets0);

        token1.safeTransfer(receiver, assets1);
    }

    /// User wants to burn 100 VaultLp (vault's token) for N worth of token0/1
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        /// NOTE: To implement
        return super.redeem(shares, receiver, owner);
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

    /// For requested N assets0 & N assets1, how much UniV2 LP do we get?
    function getLiquidityAmountOutFor(uint256 assets0, uint256 assets1)
        public
        view
        returns (uint256 poolLpAmount)
    {
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );
        poolLpAmount = min(
            ((assets0 * pair.totalSupply()) / reserveA),
            (assets1 * pair.totalSupply()) / reserveB
        );
    }

    /// Pool's LP token on contract balance
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }
}
