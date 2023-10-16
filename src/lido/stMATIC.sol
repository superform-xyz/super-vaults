// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IStMATIC} from "./interfaces/IStMATIC.sol";
import {IMATIC} from "./interfaces/IMatic.sol";

/// @title StMATIC4626
/// @notice Lido's stMATIC ERC4626 Wrapper - stMatic as Vault's underlying token (and token received after withdraw)
/// @notice Accepts MATIC, deposits into Liod's stMatic pool and mints 1:1 ERC4626-stMatic shares
/// @notice Minimal implementation providing ERC4626 interface for stMatic
/// @notice totalAsset() can be extended to return virtual MATIC balance
/// @author ZeroPoint Labs
contract StMATIC4626 is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                            LIBRARIES USAGES
    //////////////////////////////////////////////////////////////*/

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to deposit 0 assets
    error ZERO_ASSETS();

    /*//////////////////////////////////////////////////////////////
                        IMMUTABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    IStMATIC public stMatic;
    ERC20 public stMaticAsset;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

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

    function _addLiquidity(uint256 assets_, uint256) internal returns (uint256 stMaticAmount) {
        asset.approve(address(stMatic), assets_);

        /// @dev Lido's stMatic pool submit() isn't payable, MATIC is ERC20 compatible
        stMaticAmount = stMatic.submit(assets_, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit MATIC, receive ERC4626-stMatic shares for 1:1 stMatic
    function deposit(uint256 assets_, address receiver_) public override returns (uint256 shares) {
        asset.safeTransferFrom(msg.sender, address(this), assets_);

        shares = _addLiquidity(assets_, shares);

        _mint(receiver_, shares);

        emit Deposit(msg.sender, receiver_, assets_, shares);
    }

    /// @notice Mint ERC4626-stMatic shares covered 1:1 wih stMatic
    function mint(uint256 shares_, address receiver_) public override returns (uint256 assets) {
        assets = previewMint(shares_);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        shares_ = _addLiquidity(assets, shares_);

        _mint(receiver_, shares_);

        emit Deposit(msg.sender, receiver_, assets, shares_);
    }

    /// @notice Withdraw stMatic from the Vault, burn ERC4626-stMatic shares for 1:1 stMatic
    function withdraw(uint256 assets_, address receiver_, address owner_) public override returns (uint256 shares) {
        shares = previewWithdraw(assets_);

        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender];

            if (allowed != type(uint256).max) {
                allowance[owner_][msg.sender] = allowed - shares;
            }
        }

        _burn(owner_, shares);

        emit Withdraw(msg.sender, receiver_, owner_, assets_, shares);

        /// @dev Withdraw stMatic from this contract
        stMaticAsset.safeTransfer(receiver_, shares);
    }

    /// @notice Redeem ERC4626-stMatic shares for 1:1 stMatic fro the Vault
    function redeem(uint256 shares_, address receiver_, address owner_) public override returns (uint256 assets) {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender];

            if (allowed != type(uint256).max) {
                allowance[owner_][msg.sender] = allowed - shares_;
            }
        }

        if ((assets = previewRedeem(shares_)) == 0) revert ZERO_ASSETS();

        _burn(owner_, shares_);

        emit Withdraw(msg.sender, receiver_, owner_, assets, shares_);

        /// @dev Withdraw stMatic from this contract
        stMaticAsset.safeTransfer(receiver_, shares_);
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

    function convertToShares(uint256 assets_) public view virtual override returns (uint256 shares) {
        (shares,,) = stMatic.convertMaticToStMatic(assets_);
    }

    function convertToAssets(uint256 shares_) public view virtual override returns (uint256 assets) {
        (assets,,) = stMatic.convertStMaticToMatic(shares_);
    }

    function previewDeposit(uint256 assets_) public view virtual override returns (uint256) {
        return convertToShares(assets_);
    }

    function previewWithdraw(uint256 assets_) public view virtual override returns (uint256) {
        return convertToShares(assets_);
    }

    function previewRedeem(uint256 shares_) public view virtual override returns (uint256) {
        return convertToAssets(shares_);
    }

    function previewMint(uint256 shares_) public view virtual override returns (uint256) {
        return convertToAssets(shares_);
    }
}
