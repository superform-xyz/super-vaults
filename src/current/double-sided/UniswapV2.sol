// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IUniswapV2ERC20} from "./interfaces/IUniswapV2ERC20.sol";
import {UniswapV2Library} from "./utils/UniswapV2Library.sol";

// Vault (ERC4626) - totalAssets() == lpToken of Uniswap Pool
// deposit(assets) -> assets could be lpToken number? then we make previews clever
// - user needs to approve both A,B tokens in X,Y amounts
// - deposit() safeTransfersFrom A,B
// - checks are run against expected lpTokens amounts from Uniswap && || lpTokens already at balance
// withdraw() -> withdraws both A,B in accrued X+n,Y+n amounts

interface IPairV2 {}

interface IFactoryV2 {}

interface IRouterV2 {
    function getAmountsIn(uint256 amountOut, address[] memory path)
        external
        view
        returns (uint256[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );
}

/// https://v2.info.uniswap.org/pair/0xae461ca67b15dc8dc81ce7615e0320da1a9ab8d5 (DAI-USDC LP/PAIR on ETH)
contract UniswapV2WrapperERC4626 is ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public immutable manager;
    IPairV2 public immutable pair; /// pair address?
    IRouterV2 public immutable router;

    // ERC20 public tokenLp;
    ERC20 public token0;
    ERC20 public token1;

    constructor(
        ERC20 asset_,
        ERC20 token0_,
        ERC20 token1_,
        string memory name_,
        string memory symbol_,
        IRouterV2 router_,
        IPairV2 pair_
    ) ERC4626(asset_, name_, symbol_) {
        manager = msg.sender;
        pair = pair_;
        router = router_;
        token0 = token0_;
        token1 = token1_;
    }

    /// User wants to get 100 UniLP (underlying)
    /// @param assets == Assume caller called previewDeposit() first for calc on amount of assets to give approve to
    /// assets value == amount of lpToken to mint (asset) from token0 & token1 input (function has no knowledge of inputs)
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        (uint256 assets0, uint256 assets1) = getTokensToDeposit(assets);

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
        (uint256 assets0, uint256 assets1) = getTokensToDeposit(assets);

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
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        (uint256 assets0, uint256 assets1) = getTokensToDeposit(assets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

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
    /// (100 × 24689440) ÷ 24696974 == (amountA * reserveB) / reserveA = 
    function getTokensToDeposit(uint256 poolLpAmount)
        public
        view
        returns (uint256 assets0, uint256 assets1)
    {
        /// calc xy=k here, where x=a0,y=a1
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );
        // tokenABalance = reserveA
        // tokenBBalance = reserveB
        // totalSupply = pairTotalSupply()
        // amountA = (poolLpAmount / totalSupply) * reserveA
        // amountB = (poolLpAmount / totalSupply) * reserveB
        // amountB = amountA.mul(reserveB) / reserveA;
        // amountA = amountB.mul(reserveA) / reserveB;

        // UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    /// Pool's LP token on contract balance
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    ///
    function convertToShares(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    /// How much of SHARES of this VAULT user gets for ASSETS
    function previewDeposit(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        return convertToShares(assets);
    }
}
