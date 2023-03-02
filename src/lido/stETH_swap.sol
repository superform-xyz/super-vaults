// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {ICurve} from "./interfaces/ICurve.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {IWETH} from "./interfaces/IWETH.sol";

/// @title Lido's stETH ERC4626 Wrapper
/// @notice Accepts WETH through ERC4626 interface, but can also accept ETH directly through other deposit() function.
/// @notice Returns assets as ETH for brevity (community-version should return stEth)
/// @notice Assets Under Managment (totalAssets()) operates on rebasing balance, re-calculated to the current value in ETH.
/// @notice Uses ETH/stETH CurvePool for a fast-exit with 1% slippage hardcoded.
/// @author ZeroPoint Labs
contract StETHERC4626Swap is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                            LIBRARIES USAGE
    //////////////////////////////////////////////////////////////*/

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to deposit 0 assets
    error ZERO_ASSETS();

    /// @notice Thrown when trying to redeem with 0 tokens invested
    error ZERO_SHARES();

    /// @notice Thrown when trying to call a function with an invalid access
    error INVALID_ACCESS();

    /// @notice Thrown when slippage set is invalid
    error INVALID_SLIPPAGE();

    /// @notice Thrown when a 0 msg.value deposit has been tried
    error ZERO_DEPOSIT();

    /*//////////////////////////////////////////////////////////////
                      IMMUATABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    address manager;

    IStETH public stEth;
    IWETH public weth;
    ICurve public curvePool;

    uint256 public slippage;
    uint256 public immutable slippageFloat = 10000;

    int128 public immutable index_eth = 0; /// ETH
    int128 public immutable index_stEth = 1; /// stETH

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param weth_ weth address (Vault's underlying / deposit token)
    /// @param stEth_ stETH (Lido contract) address
    /// @param curvePool_ CurvePool address
    /// @param manager_ manager address
    constructor(
        address weth_,
        address stEth_,
        address curvePool_,
        address manager_
    ) ERC4626(ERC20(weth_), "ERC4626-Wrapped stETH", "wLstETH") {
        stEth = IStETH(stEth_);
        weth = IWETH(weth_);
        curvePool = ICurve(curvePool_);
        stEth.approve(address(curvePool), type(uint256).max);

        manager = manager_;
        slippage = 9900;
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                            ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets_, uint256) internal override {
        uint256 min_dy = _getSlippage(
            curvePool.get_dy(index_stEth, index_eth, assets_)
        );
        uint256 amount = curvePool.exchange(
            index_stEth,
            index_eth,
            assets_,
            min_dy
        );
    }

    function afterDeposit(uint256 ethAmount, uint256) internal override {
        uint256 stEthAmount = stEth.submit{value: ethAmount}(address(this)); /// Lido's submit() accepts only native ETH
    }

    /// @notice Standard ERC4626 deposit can only accept ERC20
    /// @notice Vault's underlying is WETH (ERC20), Lido expects ETH (Native), we make wraperooo magic
    function deposit(uint256 assets_, address receiver_)
        public
        override
        returns (uint256 shares)
    {
        if ((shares = previewDeposit(assets_)) == 0) revert ZERO_SHARES();

        asset.safeTransferFrom(msg.sender, address(this), assets_);

        weth.withdraw(assets_);

        _mint(receiver_, shares);

        emit Deposit(msg.sender, receiver_, assets_, shares);

        afterDeposit(assets_, shares);
    }

    /// @notice Deposit function accepting ETH (Native) directly
    function deposit(address receiver_)
        public
        payable
        returns (uint256 shares)
    {
        if (msg.value == 0) revert ZERO_DEPOSIT();

        if ((shares = previewDeposit(msg.value)) == 0) revert ZERO_SHARES();

        _mint(receiver_, shares);

        emit Deposit(msg.sender, receiver_, msg.value, shares);

        afterDeposit(msg.value, shares);
    }

    function mint(uint256 shares_, address receiver_)
        public
        override
        returns (uint256 assets)
    {
        assets = previewMint(shares_);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        weth.withdraw(assets);

        _mint(receiver_, shares_);

        emit Deposit(msg.sender, receiver_, assets, shares_);

        afterDeposit(assets, shares_);
    }

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

        beforeWithdraw(assets_, shares);

        _burn(owner_, shares);

        emit Withdraw(msg.sender, receiver_, owner_, assets_, shares);

        /// TODO: transfer fails because assets != beforeWithdraw eth on balance
        /// how safe is doing address(this).balance?
        SafeTransferLib.safeTransferETH(receiver_, address(this).balance);
    }

    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) public override returns (uint256 assets) {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares_;
        }

        if ((assets = previewRedeem(shares_)) == 0) revert ZERO_ASSETS();

        beforeWithdraw(assets, shares_);

        _burn(owner_, shares_);

        emit Withdraw(msg.sender, receiver_, owner_, assets, shares_);

        SafeTransferLib.safeTransferETH(receiver_, address(this).balance);
    }

    function totalAssets() public view virtual override returns (uint256) {
        return stEth.balanceOf(address(this));
    }

    function convertToShares(uint256 assets_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = totalSupply;

        return
            supply == 0 ? assets_ : assets_.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 assets_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = totalSupply;

        return
            supply == 0 ? assets_ : assets_.mulDivDown(totalAssets(), supply);
    }

    function previewMint(uint256 assets_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = totalSupply;

        return supply == 0 ? assets_ : assets_.mulDivUp(totalAssets(), supply);
    }

    function previewWithdraw(uint256 assets_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = totalSupply;

        return supply == 0 ? assets_ : assets_.mulDivUp(supply, totalAssets());
    }

    function setSlippage(uint256 amount_) external {
        if (msg.sender != manager) revert INVALID_ACCESS();
        if (amount_ > 10000 || amount_ < 9000) revert INVALID_SLIPPAGE();
        slippage = amount_;
    }

    function _getSlippage(uint256 amount_) internal view returns (uint256) {
        return (amount_ * slippage) / slippageFloat;
    }
}
