// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IPair, DexSwap} from "./utils/swapUtils.sol";
import {IStETH} from "../lido/interfaces/IStETH.sol";
import {IWETH} from "../lido/interfaces/IWETH.sol";

import "forge-std/console.sol";

/// @notice Lido's stETH ERC4626 Wrapper
/// Accepts WETH through ERC4626 interface, but can also accept ETH directly through other deposit() function.
/// Returns assets as ETH for brevity (community-version should return stEth)
/// Assets Under Managment (totalAssets()) operates on rebasing balance, re-calculated to the current value in ETH.
/// Uses ETH/stETH CurvePool for a fast-exit with 1% slippage hardcoded.
/// @author ZeroPoint Labs
contract BenqiERC4626Staking is ERC4626 {

    IStETH public sAVAX;
    IWETH public wavax;
    IPair public traderJoePool;

    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    /// @param wavax_ wavax address (Vault's underlying / deposit token)
    /// @param sAvax_ sAVAX (Benqi staking contract) address
    constructor(
        address wavax_,
        address sAvax_,
        address tradeJoePool_
    ) ERC4626(ERC20(wavax_), "ERC4626-Wrapped sAVAX", "wLsAVAX") {
        sAVAX = IStETH(sAvax_);
        wavax = IWETH(wavax_);
        traderJoePool = IPair(tradeJoePool_);
        sAVAX.approve(address(traderJoePool), type(uint256).max);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256) internal override {
        uint256 sAVAXAssets = sAVAX.getSharesByPooledAvax(assets);
        uint256 amount = DexSwap.swap(sAVAXAssets,address(sAVAX),address(wavax),address(traderJoePool));
        console.log("amount", amount);
    }

    function afterDeposit(uint256 ethAmount, uint256) internal override {
        console.log("ethAmount aD", ethAmount);
        uint256 stEthAmount = sAVAX.submit{value: ethAmount}(); /// Lido's submit() accepts only native ETH
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
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");
        
        console.log("deposit shares", shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        wavax.withdraw(assets);
        
        console.log("eth balance deposit", address(this).balance);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    /// Deposit function accepting ETH (Native) directly
    function deposit(address receiver) public payable returns (uint256 shares) {
        require(msg.value != 0, "0");

        require((shares = previewDeposit(msg.value)) != 0, "ZERO_SHARES");

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, msg.value, shares);

        afterDeposit(msg.value, shares);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {
        assets = previewMint(shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        wavax.withdraw(assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
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

        beforeWithdraw(assets, shares);

        assets = wavax.balanceOf(address(this));

        console.log("weth balance withdraw", assets);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
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

        beforeWithdraw(assets, shares);
        assets = wavax.balanceOf(address(this));
        
        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    /// @dev payable mint() is difficult to implement, probably should be dropped fully
    /// we can live with mint() being only available through weth

    // function mint(uint256 shares, address receiver, bool isPayable) public payable returns (uint256 assets) {
    //     require((ethAmount = previewMint(shares)) == msg.value, "NOT_ENOUGH");
    //     _mint(receiver, shares);
    //     emit Deposit(msg.sender, receiver, ethAmount, shares);
    //     afterDeposit(msg.value, shares);
    // }

    function totalAssets() public view virtual override returns (uint256) {
        return sAVAX.getPooledAvaxByShares(sAVAX.balanceOf(address(this)));
    }

    function convertToShares(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = totalSupply;

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = totalSupply;

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    function previewMint(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = totalSupply;

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    function previewWithdraw(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = totalSupply;

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }
}
