// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IStETH} from "./interfaces/IStETH.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import "forge-std/console.sol";

/// @title WIP: Lido's stETH ERC4626 Wrapper - stEth as Vault's underlying token (and token received after withdraw).
/// @notice Accepts WETH through ERC4626 interface, but can also accept ETH directly through different deposit() function signature.
/// Vault balance holds stEth. Value is updated for each accounting call.
/// Assets Under Managment (totalAssets()) operates on rebasing balance.
/// @dev This Wrapper is a base implementation, providing ERC4626 interface over stEth without any additional strategy.
/// hence, withdraw/redeem token from this Vault is still stEth and not Eth+accrued eth.
/// @author ZeroPoint Labs
contract StETHERC4626 is ERC4626 {

    IStETH public stEth;
    ERC20 public stEthAsset;
    IWETH public weth;

    /*//////////////////////////////////////////////////////////////
     Libraries usage
    //////////////////////////////////////////////////////////////*/

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
     Constructor
    //////////////////////////////////////////////////////////////*/

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
        console.log("ethAmount addLiq", ethAmount);
        stEthAmount = stEth.submit{value: ethAmount}(address(this));
        console.log("stEthAmount addLiq", stEthAmount);
    }

    /*//////////////////////////////////////////////////////////////
     ERC4626 overrides
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit WETH. Standard ERC4626 deposit can only accept ERC20.
    /// Vault's underlying is WETH (ERC20), Lido expects ETH (Native), we use WETH wraper
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");
        
        asset.safeTransferFrom(msg.sender, address(this), assets);

        weth.withdraw(assets);
        
        console.log("eth balance deposit", address(this).balance);

        addLiquidity(assets, shares);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

    }

    /// @notice Deposit function accepting ETH (Native) directly
    function deposit(address receiver) public payable returns (uint256 shares) {
        require((shares = previewDeposit(msg.value)) != 0, "ZERO_SHARES");

        shares = addLiquidity(msg.value, shares);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, msg.value, shares);

    }

    /// @notice Mint amount of stEth / ERC4626-stEth
    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {
        assets = previewMint(shares);

        console.log("mint assets", assets);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        weth.withdraw(assets);

        addLiquidity(assets, shares);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

    }

    /// @notice Withdraw amount of ETH represented by stEth / ERC4626-stEth. Output token is stEth.
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

    /// @notice Redeem exact amount of stEth / ERC4626-stEth from this Vault. Output token is stEth.
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

    /// @notice stEth is used as AUM of this Vault
    function totalAssets() public view virtual override returns (uint256) {
        return stEth.balanceOf(address(this));
    }

    /// @notice Calculate amount of stEth you get in exchange for ETH (WETH)
    function convertToShares(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return stEth.getSharesByPooledEth(assets);
    }

    /// @notice Calculate amount of ETH you get in exchange for stEth (ERC4626-stEth)
    /// Used as "virtual" amount in base implementation. No ETH is ever withdrawn.
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

    function previewWithdraw(uint256 assets)
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

}
