// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IPair, DexSwap} from "./utils/swapUtils.sol";
import {IStakedAvax} from "./interfaces/IStakedAvax.sol";
import {IWETH} from "../lido/interfaces/IWETH.sol";

import "forge-std/console.sol";

/// @notice Benqi AVAX Liquid Staking Adapter
/// Accepts WAVAX to deposit into Benqi's staking contract - sAVAX, provides ERC4626 interface over token
/// Withdraw/Redeem to AVAX is not a part of this base contract. Withdraw/Redeem is only possible to sAVAX token.
/// Two possible ways of extending this contract: https://docs.benqi.fi/benqi-liquid-staking/staking-and-unstaking
/// In contrast to Lido's stETH, sAVAX can be Unstaked with 15d cooldown period. TODO: Extend with Timelock
/// @author ZeroPoint Labs
contract BenqiERC4626Staking is ERC4626 {
    IStakedAvax public sAVAX;
    IWETH public wavax;
    ERC20 public sAvaxAsset;

    /*//////////////////////////////////////////////////////////////
     Libraries usage
    //////////////////////////////////////////////////////////////*/

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
     Constructor
    //////////////////////////////////////////////////////////////*/

    /// @param wavax_ wavax address (Vault's underlying / deposit token)
    /// @param sAvax_ sAVAX (Benqi staking contract) address
    constructor(address wavax_, address sAvax_)
        // address tradeJoePool_
        ERC4626(ERC20(wavax_), "ERC4626-Wrapped sAVAX", "wLsAVAX")
    {
        sAVAX = IStakedAvax(sAvax_);
        sAvaxAsset = ERC20(sAvax_);
        wavax = IWETH(wavax_);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function addLiquidity(uint256 wAvaxAmt, uint256)
        internal
        returns (uint256 sAvaxAmt)
    {
        console.log("ethAmount aD", wAvaxAmt);
        sAvaxAmt = sAVAX.submit{value: wAvaxAmt}();
        console.log("stEthAmount aD", sAvaxAmt);
    }

    /*//////////////////////////////////////////////////////////////
     ERC4626 overrides
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit AVAX. Standard ERC4626 deposit can only accept ERC20.
    /// Vault's underlying is WAVAX (ERC20), Benqi expects AVAX (Native), we use WAVAX wraper
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        asset.safeTransferFrom(msg.sender, address(this), assets);

        wavax.withdraw(assets);

        /// @dev Difference from Lido fork is useful return amount here
        shares = addLiquidity(assets, shares);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Deposit function accepting WAVAX (Native) directly
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

        asset.safeTransferFrom(msg.sender, address(this), assets);

        wavax.withdraw(assets);

        shares = addLiquidity(assets, shares);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Withdraw amount of ETH represented by stEth / ERC4626-stEth. Output token is stEth.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        /// @dev In base implementation, previeWithdraw allows to get sAvax amount to withdraw for virtual amount from convertToAssets
        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        sAvaxAsset.safeTransfer(receiver, assets);
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

        sAvaxAsset.safeTransfer(receiver, shares);
    }

    /// @notice stEth is used as AUM of this Vault
    function totalAssets() public view virtual override returns (uint256) {
        return sAVAX.balanceOf(address(this));
    }

    /// @notice Calculate amount of stEth you get in exchange for ETH (WETH)
    function convertToShares(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return sAVAX.getSharesByPooledAvax(assets);
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
        return sAVAX.getPooledAvaxByShares(shares);
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

    /// @notice maxWithdraw is equal to shares balance only in base implementation
    /// That is because output token is still stEth and not ETH+yield
    function maxWithdraw(address owner) public view override returns (uint256) {
        return balanceOf[owner];
    }

    /// @notice maxRedeem is equal to shares balance only in base implementation
    /// That is because output token is still stEth and not ETH+yield
    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf[owner];
    }
}
