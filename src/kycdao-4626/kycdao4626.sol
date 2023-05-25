// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IKycValidity} from "./interfaces/IKycValidity.sol";

/// @title kycDAO4626
/// @notice NFT-gated ERC-4626 using KYCDAO https://docs.kycdao.xyz/smartcontracts/evm/
/// @author ZeroPoint Labs
contract kycDAO4626 is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    IKycValidity public kycValidity;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    /// @dev Error if msg.sender doesn't have a valid KYC Token
    error NO_VALID_KYC_TOKEN();

    /// @notice Thrown when trying to deposit 0 assets
    error ZERO_ASSETS();

    /// @notice Thrown when trying to deposit 0 assets
    error ZERO_SHARES();

    /*//////////////////////////////////////////////////////////////
                                MODIFERS
    //////////////////////////////////////////////////////////////*/

    modifier hasKYC() {
        if (!kycCheck(msg.sender)) revert NO_VALID_KYC_TOKEN();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor
    /// @param asset_ The ERC20 asset to wrap
    /// @param kycValidity_ The address of the KYCDAO contract
    constructor(
        ERC20 asset_,
        address kycValidity_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        kycValidity = IKycValidity(kycValidity_);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function deposit(
        uint256 assets_,
        address receiver_
    ) public override hasKYC returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        if ((shares = previewDeposit(assets_)) == 0) revert ZERO_SHARES();

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets_);

        _mint(receiver_, shares);

        emit Deposit(msg.sender, receiver_, assets_, shares);

        afterDeposit(assets_, shares);
    }

    function mint(
        uint256 shares_,
        address receiver_
    ) public override hasKYC returns (uint256 assets) {
        assets = previewMint(shares_); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver_, shares_);

        emit Deposit(msg.sender, receiver_, assets, shares_);

        afterDeposit(assets, shares_);
    }

    function withdraw(
        uint256 assets_,
        address receiver_,
        address owner_
    ) public override hasKYC returns (uint256 shares) {
        shares = previewWithdraw(assets_); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets_, shares);

        _burn(owner_, shares);

        emit Withdraw(msg.sender, receiver_, owner_, assets_, shares);

        asset.safeTransfer(receiver_, assets_);
    }

    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) public override hasKYC returns (uint256 assets) {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares_;
        }

        // Check for rounding error since we round down in previewRedeem.
        if ((assets = previewRedeem(shares_)) == 0) revert ZERO_ASSETS();

        beforeWithdraw(assets, shares_);

        _burn(owner_, shares_);

        emit Withdraw(msg.sender, receiver_, owner_, assets, shares_);

        asset.safeTransfer(receiver_, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 METADATA GENERATION
    //////////////////////////////////////////////////////////////*/

    function _vaultName(
        ERC20 asset_
    ) internal view virtual returns (string memory vaultName) {
        vaultName = string.concat("kycERC4626-", asset_.symbol());
    }

    function _vaultSymbol(
        ERC20 asset_
    ) internal view virtual returns (string memory vaultSymbol) {
        vaultSymbol = string.concat("kyc", asset_.symbol());
    }

    /*//////////////////////////////////////////////////////////////
                        KYC DAO GETTERS
    //////////////////////////////////////////////////////////////*/

    function kycCheck(address user_) public view returns (bool) {
        return kycValidity.hasValidToken(user_);
    }

    function kycValidityAddress() public view returns (address) {
        return address(kycValidity);
    }
}
