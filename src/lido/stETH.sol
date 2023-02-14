// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IStETH} from "./interfaces/IStETH.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import "forge-std/console.sol";

/// @notice Lido's stETH ERC4626 Wrapper - stEth as Vault's underlying token (and token received after withdraw).
/// Accepts WETH through ERC4626 interface, but can also accept ETH directly through different deposit() function signature.
/// Vault balance holds stEth. Value is updated for each accounting call.
/// Assets Under Managment (totalAssets()) operates on rebasing balance.
/// This stEth ERC4626 wrapper is prefered way to deal with stEth wrapping over other solutions.
/// @author ZeroPoint Labs
contract StETHERC4626 is ERC4626 {

    IStETH public stEth;
    ERC20 public stEthAsset;
    IWETH public weth;

    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    /// @param weth_ weth address (Vault's underlying / deposit token)
    /// @param stEth_ stETH (Lido contract) address
    constructor(
        address weth_,
        address stEth_
    ) ERC4626(ERC20(weth_), "ERC4626-Wrapped stETH", "wLstETH") {
        stEth = IStETH(stEth_);
        stEthAsset = ERC20(stEth_);
        weth = IWETH(weth_);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function addLiquidity(uint256 ethAmount, uint256) internal returns (uint256 stEthAmount) {
        console.log("ethAmount aD", ethAmount);
        /// Lido's submit() accepts only native ETH
        stEthAmount = stEth.submit{value: ethAmount}(address(this));
        console.log("stEthAmount aD", stEthAmount);
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    /// Standard ERC4626 deposit can only accept ERC20
    /// Vault's underlying is WETH (ERC20), Lido expects ETH (Native), we make wraperooo magic
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        
        asset.safeTransferFrom(msg.sender, address(this), assets);

        weth.withdraw(assets);
        
        console.log("eth balance deposit", address(this).balance);

        shares = addLiquidity(assets, shares);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

    }

    /// Deposit function accepting ETH (Native) directly
    function deposit(address receiver) public payable returns (uint256 shares) {
        require(msg.value != 0, "0");

        shares = addLiquidity(msg.value, shares);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, msg.value, shares);

    }

    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {
        assets = previewMint(shares);

        console.log("mint assets", assets);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        weth.withdraw(assets);

        shares = addLiquidity(assets, shares);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets);

        console.log("shares withdraw", shares);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        console.log("stEth balance withdraw", stEthAsset.balanceOf(address(this)));

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        stEthAsset.safeTransfer(receiver, assets);

    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        stEthAsset.safeTransfer(receiver, assets);
    }

    /// stETH as AUM. Rebasing!
    function totalAssets() public view virtual override returns (uint256) {
        return stEth.balanceOf(address(this));
    }

    function convertToShares(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return stEth.getSharesByPooledEth(assets);
    }

    function convertToAssets(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return stEth.getPooledEthByShares(shares);
    }

    function previewDeposit(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return convertToAssets(shares);
    }

    function previewMint(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return convertToShares(assets);
    }
}
