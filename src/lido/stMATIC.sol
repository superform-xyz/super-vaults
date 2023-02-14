// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IStMATIC} from "./interfaces/IStMATIC.sol";
import {IMATIC} from "./interfaces/IMatic.sol";

import "forge-std/console.sol";

/// @notice Lido's stMATIC ERC4626 Wrapper - stMatic as Vault's underlying token (and token received after withdraw).
/// Accepts MATIC through ERC4626 interface
/// Vault balance holds stMatic. Value is updated for each accounting call.
/// @author ZeroPoint Labs
contract StMATIC4626 is ERC4626 {

    IStMATIC public stMatic;
    ERC20 public stMaticAsset;

    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    /// @param matic_ matic address (Vault's underlying / deposit token)
    /// @param stMatic_ stMatic (Lido contract) address
    constructor(address matic_, address stMatic_)
        ERC4626(ERC20(matic_), "ERC4626-Wrapped stMatic", "wLstMatic")
    {
        stMatic = IStMATIC(stMatic_);
        stMaticAsset = ERC20(stMatic_);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function afterDeposit(uint256 assets, uint256) internal override {
        console.log("ethAmount aD", assets);
        asset.approve(address(stMatic), assets);
        /// Lido's stMatic pool submit() isn't payable, MATIC is ERC20 compatible
        /// TODO - check the referal address - do we need it?
        uint256 stEthAmount = stMatic.submit(assets, address(0));
        console.log("stEthAmount aD", stEthAmount);
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    /// Standard ERC4626 deposit can only accept ERC20
    /// Vault's underlying is MATIC (ERC20)
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        console.log("deposit shares", shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);

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

        console.log(
            "stMatic balance withdraw",
            stMaticAsset.balanceOf(address(this))
        );

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        stMaticAsset.safeTransfer(receiver, assets);
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

        stMaticAsset.safeTransfer(receiver, assets);
    }

    /// stMatic as AUM. Non-rebasing!
    function totalAssets() public view virtual override returns (uint256) {
        return stMatic.balanceOf(address(this));
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
