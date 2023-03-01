// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "../interfaces/IUniswapV2Router.sol";
import {UniswapV2Library} from "../utils/UniswapV2Library.sol";

/// @title UniswapV2WrapperERC4626
/// @notice Custom ERC4626 Wrapper for UniV2 Pools without swapping, accepting token0/token1 transfers
/// @dev WARNING: Change your assumption about asset/share in context of deposit/mint/redeem/withdraw
/// @notice Basic flow description:
/// @notice Vault (ERC4626) - totalAssets() == lpToken of Uniswap Pool
/// @notice deposit(assets) -> assets == lpToken amount to receive
/// @notice - user needs to approve both A,B tokens in X,Y amounts (see getLiquidityAmounts / getAssetsAmounts functions)
/// @notice - check is run if A,B covers requested Z amount of UniLP
/// @notice - deposit() safeTransfersFrom A,B to _min Z amount of UniLP
/// @notice withdraw() -> withdraws both A,B in accrued X+n,Y+n amounts, burns Z amount of UniLP (or Vault's LP, those are 1:1)
/// @dev https://v2.info.uniswap.org/pair/0xae461ca67b15dc8dc81ce7615e0320da1a9ab8d5 (DAI-USDC LP/PAIR on ETH)
/// @author ZeroPoint Labs
contract UniswapV2WrapperERC4626 is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                        LIBRARIES USAGES
    //////////////////////////////////////////////////////////////*/
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                      IMMUTABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable manager;

    uint256 public slippage;
    uint256 public immutable slippageFloat = 10000;

    IUniswapV2Pair public immutable pair;
    IUniswapV2Router public immutable router;

    ERC20 public token0;
    ERC20 public token1;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param name_ ERC4626 name
    /// @param symbol_ ERC4626 symbol
    /// @param asset_ ERC4626 asset (LP Token)
    /// @param token0_ ERC20 token0
    /// @param token1_ ERC20 token1
    /// @param router_ UniswapV2Router
    /// @param pair_ UniswapV2Pair
    /// @param slippage_ slippage param
    constructor(
        string memory name_,
        string memory symbol_,
        ERC20 asset_, /// Pair address (to opti)
        ERC20 token0_,
        ERC20 token1_,
        IUniswapV2Router router_,
        IUniswapV2Pair pair_, /// Pair address (to opti)
        uint256 slippage_
    ) ERC4626(asset_, name_, symbol_) {
        manager = msg.sender;
        pair = pair_;
        router = router_;
        token0 = token0_;
        token1 = token1_;

        slippage = slippage_;
    }

    /// @param amount_ amount of slippage
    function setSlippage(uint256 amount_) external {
        require(msg.sender == manager, "owner");
        require(amount_ < 10000 && amount_ > 9000); /// 10% max slippage
        slippage = amount_;
    }

    /// @param amount_ amount of slippage
    function getSlippage(uint256 amount_) internal view returns (uint256) {
        return (amount_ * slippage) / slippageFloat;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets_, uint256 shares_)
        internal
        override
    {
        (uint256 assets0, uint256 assets1) = getAssetsAmounts(assets_);

        pair.approve(address(router), shares_);

        /// temp implementation, we should call directly on a pair
        router.removeLiquidity(
            address(token0),
            address(token1),
            assets_,
            assets0 - getSlippage(assets0),
            assets1 - getSlippage(assets1),
            address(this),
            block.timestamp + 100
        );
    }

    function afterDeposit(uint256 assets_, uint256) internal override {
        (uint256 assets0, uint256 assets1) = getAssetsAmounts(assets_);

        /// temp should be more elegant. better than max approve though
        token0.approve(address(router), assets0);
        token1.approve(address(router), assets1);

        /// temp implementation, we should call directly on a pair
        router.addLiquidity(
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

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @notice User wants to get 100 UniLP (underlying)
    /// @notice REQUIREMENT: Calculate amount of assets and have enough of assets0/1 to cover this amount for LP requested (slippage!)
    /// @param getUniLpFromAssets_ == Assume caller called getAssetsAmounts() first for calc on amount of assets to give approve to
    /// @param receiver_ - Who will receive shares (Standard ERC4626)
    /// @return shares - Of this Vault (Standard ERC4626)
    function deposit(uint256 getUniLpFromAssets_, address receiver_)
        public
        override
        returns (uint256 shares)
    {
        /// From 100 uniLP msg.sender gets N shares (of this Vault)
        require(
            (shares = previewDeposit(getUniLpFromAssets_)) != 0,
            "ZERO_SHARES"
        );

        /// Ideally, msg.sender should call this function beforehand to get correct "assets" amount
        (uint256 assets0, uint256 assets1) = getAssetsAmounts(
            getUniLpFromAssets_
        );

        /// Best if we approve exact amounts, but because of UniV2 _min() we can sometimes approve to much/to little
        token0.safeTransferFrom(msg.sender, address(this), assets0);

        token1.safeTransferFrom(msg.sender, address(this), assets1);

        _mint(receiver_, shares);

        /// Custom assumption about assets changes assumptions about this event
        emit Deposit(msg.sender, receiver_, getUniLpFromAssets_, shares);

        afterDeposit(getUniLpFromAssets_, shares);
    }

    /// @notice User want to get 100 VaultLP (vault's token) worth N UniLP (Standard ERC4626 behavior, 'get me N amount of shares of this Vault')
    /// @param sharesOfThisVault_ shares value == amount of Vault token (shares) to mint from requested lpToken, but...
    ///        because this is 1:1 with LPTOKEN amount on this balance, function behaves like deposit() anyways
    /// @param receiver_ == receiver of shares (Vault token)
    /// @return assets == amount of LPTOKEN minted (1:1 with sharesOfThisVault_ input)
    function mint(uint256 sharesOfThisVault_, address receiver_)
        public
        override
        returns (uint256 assets)
    {
        assets = previewMint(sharesOfThisVault_);

        (uint256 assets0, uint256 assets1) = getAssetsAmounts(assets);

        token0.safeTransferFrom(msg.sender, address(this), assets0);

        token1.safeTransferFrom(msg.sender, address(this), assets1);

        _mint(receiver_, sharesOfThisVault_);

        /// Custom assumption about assets changes assumptions about this event
        emit Deposit(msg.sender, receiver_, assets, sharesOfThisVault_);

        afterDeposit(assets, sharesOfThisVault_);
    }

    /// @notice User wants to burn 100 UniLP (underlying) for N worth of token0/1
    function withdraw(
        uint256 assets_, // amount of underlying asset (pool Lp) to withdraw
        address receiver_,
        address owner_
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets_);

        (uint256 assets0, uint256 assets1) = getAssetsAmounts(assets_);

        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets_, shares);

        _burn(owner_, shares);

        /// Custom assumption about assets changes assumptions about this event
        emit Withdraw(msg.sender, receiver_, owner_, assets_, shares);

        token0.safeTransfer(receiver_, assets0);

        token1.safeTransfer(receiver_, assets1);
    }

    /// @notice User wants to burn 100 VaultLp (vault's token) for N worth of token0/1
    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) public override returns (uint256 assets) {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares_;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares_)) != 0, "ZERO_ASSETS");

        (uint256 assets0, uint256 assets1) = getAssetsAmounts(assets);

        beforeWithdraw(assets, shares_);

        _burn(owner_, shares_);

        emit Withdraw(msg.sender, receiver_, owner_, assets, shares_);

        token0.safeTransfer(receiver_, assets0);

        token1.safeTransfer(receiver_, assets1);
    }

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
        /// amount of token0 to provide to receive poolLpAmount_
        assets0 = (reserveA * poolLpAmount_) / pairSupply;
        /// amount of token1 to provide to receive poolLpAmount_
        assets1 = (reserveB * poolLpAmount_) / pairSupply;
    }

    /// @notice For requested N assets0 & N assets1, how much UniV2 LP do we get?
    function getLiquidityAmountOutFor(uint256 assets0_, uint256 assets1_)
        public
        view
        returns (uint256 poolLpAmount)
    {
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(
            address(pair),
            address(token0),
            address(token1)
        );
        poolLpAmount = _min(
            ((assets0_ * pair.totalSupply()) / reserveA),
            (assets1_ * pair.totalSupply()) / reserveB
        );
    }

    /// Pool's LP token on contract balance
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }
}
