// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IWETH} from "../interfaces/IWETH.sol";
import {IRETH} from "../interfaces/IReth.sol";
import {IRSTORAGE} from "../interfaces/IRstorage.sol";

import "forge-std/console.sol";

/// @notice RocketPool's rETH ERC4626 Wrapper
/// @author ZeroPoint Labs
contract rEthERC4626 is ERC4626 {

    IWETH public weth;
    IRETH public rEth;
    IRSTORAGE public rStorage;
    ERC20 public rEthAsset;

    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    /// @param weth_ weth address (Vault's underlying / deposit token)
    /// @param rStorage_ rocketPool Storage contract address to read current implementation details
    constructor(
        address weth_,
        address rStorage_
    ) ERC4626(ERC20(weth_), "ERC4626-Wrapped rEth", "wLstReth") {
        rStorage = IRSTORAGE(rStorage_);
        weth = IWETH(weth_);

        /// Get address of Deposit pool from address of rStorage on deployment
        address rocketDepositPoolAddress = rStorage.getAddress(keccak256(abi.encodePacked("contract.address", "rocketDepositPool")));
        rEth = IRETH(rocketDepositPoolAddress);

        /// Get address of rETH ERC20 token
        address rocketTokenRETHAddress = rStorage.getAddress(keccak256(abi.encodePacked("contract.address", "rocketTokenRETH")));
        rEthAsset = ERC20(rocketTokenRETHAddress);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256) internal override {
        /// NOTE: Empty. We withdraw stMatic from the contract balance
    }

    function afterDeposit(uint256 assets, uint256) internal override {
        console.log("ethAmount aD", assets);
        rEth.deposit{value: assets}();
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    /// Standard ERC4626 deposit can only accept ERC20
    /// Vault's underlying is rETH
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");
        
        console.log("deposit shares", shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        weth.withdraw(assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {
        assets = previewMint(shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        weth.withdraw(assets);

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

        console.log("rEth balance withdraw", rEthAsset.balanceOf(address(this)));

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        rEthAsset.safeTransfer(receiver, assets);

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

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        rEthAsset.safeTransfer(receiver, assets);
    }

    /// rEth as AUM. Non-rebasing!
    function totalAssets() public view virtual override returns (uint256) {
        return rEth.balanceOf(address(this));
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
