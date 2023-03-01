// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IStMATIC} from "./interfaces/IStMATIC.sol";
import {IMATIC} from "./interfaces/IMatic.sol";

/// @notice Lido's stMATIC ERC4626 Wrapper - stMatic as Vault's underlying token (and token received after withdraw)
/// Accepts MATIC, deposits into Liod's stMatic pool and mints 1:1 ERC4626-stMatic shares
/// Minimal implementation providing ERC4626 interface for stMatic
/// totalAsset() can be extended to return virtual MATIC balance
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
        ERC4626(ERC20(matic_), "ERC4626-Wrapped stMatic", "ERC4626-stMatic")
    {
        stMatic = IStMATIC(stMatic_);
        stMaticAsset = ERC20(stMatic_);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function addLiquidity(uint256 assets, uint256)
        internal
        returns (uint256 stMaticAmount)
    {
        asset.approve(address(stMatic), assets);

        /// @dev Lido's stMatic pool submit() isn't payable, MATIC is ERC20 compatible
        stMaticAmount = stMatic.submit(assets, address(0));
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    /// @notice Deposit MATIC, receive ERC4626-stMatic shares for 1:1 stMatic
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        asset.safeTransferFrom(msg.sender, address(this), assets);

        shares = addLiquidity(assets, shares);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Mint ERC4626-stMatic shares covered 1:1 wih stMatic
    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {
        assets = previewMint(shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        shares = addLiquidity(assets, shares);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Withdraw stMatic from the Vault, burn ERC4626-stMatic shares for 1:1 stMatic
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        /// @dev Withdraw stMatic from this contract
        stMaticAsset.safeTransfer(receiver, shares);
    }

    /// @notice Redeem ERC4626-stMatic shares for 1:1 stMatic fro the Vault
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

        /// @dev Withdraw stMatic from this contract
        stMaticAsset.safeTransfer(receiver, shares);
    }

    /// stMatic as AUM. Non-rebasing!
    function totalAssets() public view virtual override returns (uint256) {
        return stMatic.balanceOf(address(this));
    }

    /*///////////////////////////////////////////////////////////////
                   
                   PREVIEW FUNCTIONS USED AS WRAPPERS

                   Preview functions in this implementation
                   are not used in deposit/mint flow as 
                   ERC4626 shares of this contract are 1:1
                   with stMatic. 
    
    //////////////////////////////////////////////////////////////*/
    
    function convertToShares(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256 shares)
    {
        (shares, , ) = stMatic.convertMaticToStMatic(assets);
    }

    function convertToAssets(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256 assets)
    {
        (assets, , ) = stMatic.convertStMaticToMatic(shares);
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
