// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IPair, DexSwap} from "./utils/swapUtils.sol";
import {IStakedAvax} from "./interfaces/IStakedAvax.sol";
import {IWETH} from "../lido/interfaces/IWETH.sol";

/// @title BenqiERC4626Staking
/// @notice Accepts WAVAX to deposit into Benqi's staking contract - sAVAX, provides ERC4626 interface over token
/// @notice Withdraw/Redeem to AVAX is not a part of this base contract. Withdraw/Redeem is only possible to sAVAX token.
/// @notice Two possible ways of extending this contract: https://docs.benqi.fi/benqi-liquid-staking/staking-and-unstaking
/// @notice In contrast to Lido's stETH, sAVAX can be Unstaked with 15d cooldown period.
/// @author ZeroPoint Labs
contract BenqiERC4626Staking is ERC4626 {
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

    /*//////////////////////////////////////////////////////////////
                      IMMUATABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/
    IStakedAvax public sAVAX;
    IWETH public wavax;
    ERC20 public sAvaxAsset;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
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

    function _addLiquidity(uint256 wAvaxAmt_, uint256)
        internal
        returns (uint256 sAvaxAmt)
    {
        sAvaxAmt = sAVAX.submit{value: wAvaxAmt_}();
    }

    /*//////////////////////////////////////////////////////////////
                            ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit AVAX. Standard ERC4626 deposit can only accept ERC20.
    /// @notice Vault's underlying is WAVAX (ERC20), Benqi expects AVAX (Native), we use WAVAX wraper
    function deposit(uint256 assets_, address receiver_)
        public
        override
        returns (uint256 shares)
    {
        if ((shares = previewDeposit(assets_)) == 0) revert ZERO_SHARES();

        asset.safeTransferFrom(msg.sender, address(this), assets_);

        wavax.withdraw(assets_);

        /// @dev Difference from Lido fork is useful return amount here
        shares = _addLiquidity(assets_, shares);

        _mint(receiver_, shares);

        emit Deposit(msg.sender, receiver_, assets_, shares);
    }

    /// @notice Deposit function accepting WAVAX (Native) directly
    function deposit(address receiver_)
        public
        payable
        returns (uint256 shares)
    {
        if ((shares = previewDeposit(msg.value)) == 0) revert ZERO_SHARES();

        shares = _addLiquidity(msg.value, shares);

        _mint(receiver_, shares);

        emit Deposit(msg.sender, receiver_, msg.value, shares);
    }

    /// @notice Mint amount of stEth / ERC4626-stEth
    function mint(uint256 shares_, address receiver_)
        public
        override
        returns (uint256 assets)
    {
        assets = previewMint(shares_);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        wavax.withdraw(assets);

        shares_ = _addLiquidity(assets, shares_);

        _mint(receiver_, shares_);

        emit Deposit(msg.sender, receiver_, assets, shares_);
    }

    /// @notice Withdraw amount of ETH represented by stEth / ERC4626-stEth. Output token is stEth.
    function withdraw(
        uint256 assets_,
        address receiver_,
        address owner_
    ) public override returns (uint256 shares) {
        /// @dev In base implementation, previeWithdraw allows to get sAvax amount to withdraw for virtual amount from convertToAssets
        shares = previewWithdraw(assets_);

        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares;
        }

        _burn(owner_, shares);

        emit Withdraw(msg.sender, receiver_, owner_, assets_, shares);

        sAvaxAsset.safeTransfer(receiver_, assets_);
    }

    /// @notice Redeem exact amount of stEth / ERC4626-stEth from this Vault. Output token is stEth.
    function redeem(
        uint256 shares_,
        address receiver,
        address owner_
    ) public override returns (uint256 assets) {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares_;
        }

        if ((assets = previewRedeem(shares_)) == 0) revert ZERO_ASSETS();

        _burn(owner_, shares_);

        emit Withdraw(msg.sender, receiver, owner_, assets, shares_);

        sAvaxAsset.safeTransfer(receiver, shares_);
    }

    /// @notice stEth is used as AUM of this Vault
    function totalAssets() public view virtual override returns (uint256) {
        return sAVAX.balanceOf(address(this));
    }

    /// @notice Calculate amount of stEth you get in exchange for ETH (WETH)
    function convertToShares(uint256 assets_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return sAVAX.getSharesByPooledAvax(assets_);
    }

    /// @notice Calculate amount of ETH you get in exchange for stEth (ERC4626-stEth)
    /// @notice Used as "virtual" amount in base implementation. No ETH is ever withdrawn.
    function convertToAssets(uint256 shares_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return sAVAX.getPooledAvaxByShares(shares_);
    }

    function previewDeposit(uint256 assets_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return convertToShares(assets_);
    }

    function previewWithdraw(uint256 assets_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return convertToShares(assets_);
    }

    function previewRedeem(uint256 shares_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return convertToAssets(shares_);
    }

    function previewMint(uint256 shares_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return convertToAssets(shares_);
    }

    /// @notice maxWithdraw is equal to shares balance only in base implementation
    /// @notice That is because output token is still stEth and not ETH+yield
    function maxWithdraw(address owner_)
        public
        view
        override
        returns (uint256)
    {
        return balanceOf[owner_];
    }

    /// @notice maxRedeem is equal to shares balance only in base implementation
    /// @notice That is because output token is still stEth and not ETH+yield
    function maxRedeem(address owner_) public view override returns (uint256) {
        return balanceOf[owner_];
    }
}
