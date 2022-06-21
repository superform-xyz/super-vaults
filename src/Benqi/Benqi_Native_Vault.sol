// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
// import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {console} from "../test/utils/Console.sol";
import {WrappedNative} from "../interfaces/WrappedNative.sol";

abstract contract CEther is ERC20 {
    function comptroller() external view virtual returns (address);

    function getCash() external view virtual returns (uint256);

    function getAccountSnapshot(address)
        external
        view
        virtual
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );
    function redeemUnderlying(uint256) external virtual returns (uint256);
    function mint() external payable virtual;
    
    function exchangeRateStored() external virtual view returns (uint);
}

interface Unitroller {
    function mintGuardianPaused(address cEther)
        external
        view
        returns (bool);
    function supplyCaps(address cEtherAddress) external view returns(uint256);
}

contract BenqiNativeVault is ERC4626 {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /// @notice cEther token reference
    CEther public immutable cEther;

    /// @notice reference to the Unitroller of the cEther token
    Unitroller public immutable unitroller;
    /// @notice CompoundERC4626 constructor
    /// @param _cEther Compound cEther to wrap
    /// @param name ERC20 name of the vault shares token
    /// @param symbol ERC20 symbol of the vault shares token
    constructor(
        address _cEther,
        string memory name,
        string memory symbol,
        address _wrappedNative
    ) ERC4626(ERC20(_wrappedNative), name, symbol) {
        cEther = CEther(_cEther);
        unitroller = Unitroller(cEther.comptroller());
    }

    function beforeWithdraw(uint256 underlyingAmount, uint256)
        internal
        override
    {
        // Withdraw the underlying tokens from the cEther.
        require(
            cEther.redeemUnderlying(underlyingAmount) == 0,
            "REDEEM_FAILED"
        );
    }

    function viewUnderlyingBalanceOf() internal view returns (uint256) {
        return cEther.balanceOf(address(this)).mulWadDown(cEther.exchangeRateStored());
    }

    function afterDeposit(uint256 underlyingAmount, uint256) internal override {
        WrappedNative(address(asset)).withdraw(underlyingAmount);
            // mint tokens
        cEther.mint{value: underlyingAmount}();
    }

    function depositNative(address receiver) public payable returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(msg.value)) != 0, "ZERO_SHARES");

        WrappedNative(address(asset)).deposit{value: msg.value}();
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, msg.value, shares);

        afterDeposit(msg.value, shares);
    }

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    function totalAssets() public view override returns (uint256) {
        return viewUnderlyingBalanceOf();
    }

    /// @notice maximum amount of assets that can be deposited.
    /// This is capped by the amount of assets the cEther can be
    /// supplied with.
    /// This is 0 if minting is paused on the cEther.
    function maxDeposit(address) public view override returns (uint256) {
        address cEtherAddress = address(cEther);

        if (unitroller.mintGuardianPaused(cEtherAddress)) return 0;

        uint256 supplyCap = unitroller.supplyCaps(cEtherAddress);
        if (supplyCap == 0) return type(uint256).max;

        uint256 assetsDeposited = cEther.totalSupply().mulWadDown(
            cEther.exchangeRateStored()
        );
        return supplyCap - assetsDeposited;
    }

    /// @notice maximum amount of shares that can be minted.
    /// This is capped by the amount of assets the cEther can be
    /// supplied with.
    /// This is 0 if minting is paused on the cEther.
    function maxMint(address) public view override returns (uint256) {
        address cEtherAddress = address(cEther);

        if (unitroller.mintGuardianPaused(cEtherAddress)) return 0;

        uint256 supplyCap = unitroller.supplyCaps(cEtherAddress);
        if (supplyCap == 0) return type(uint256).max;

        uint256 assetsDeposited = cEther.totalSupply().mulWadDown(
            cEther.exchangeRateStored()
        );
        return convertToShares(supplyCap - assetsDeposited);
    }

    /// @notice Maximum amount of assets that can be withdrawn.
    /// This is capped by the amount of cash available on the cEther,
    /// if all assets are borrowed, a user can't withdraw from the vault.
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 cash = cEther.getCash();
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    /// @notice Maximum amount of shares that can be redeemed.
    /// This is capped by the amount of cash available on the cEther,
    /// if all assets are borrowed, a user can't redeem from the vault.
    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 cash = cEther.getCash();
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    /// @notice withdraw assets of the owner.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        WrappedNative(address(asset)).deposit{value:assets}();
        asset.safeTransfer(receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        WrappedNative(address(asset)).deposit{value:assets}();
        asset.safeTransfer(receiver, assets);
    }

    receive() external payable {}
}
