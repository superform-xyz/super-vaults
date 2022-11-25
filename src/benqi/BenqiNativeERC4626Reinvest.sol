// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ICEther} from "./compound/ICEther.sol";
import {LibCompound} from "./compound/LibCompound.sol";
import {IComptroller} from "./compound/IComptroller.sol";

import {DexSwap} from "./utils/swapUtils.sol";
import {WrappedNative} from "./utils/wrappedNative.sol";

/// @title BenqiERC4626Reinvest - Custom implementation of yield-daddy wrappers with flexible reinvesting logic
/// @notice Extended with payable function to accept native token transfer
contract BenqiNativeERC4626Reinvest is ERC4626 {
    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using LibCompound for ICEther;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint256 internal constant NO_ERROR = 0;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice cEther token reference
    ICEther public immutable cEther;

    /// @notice The Compound comptroller contract
    IComptroller public immutable comptroller;

    /// @notice Access Control for harvest() route
    address public immutable manager;

    /// @notice The COMP-like token contract
    ERC20 public immutable reward;

    /// @notice Pointer to swapInfo
    swapInfo public SwapInfo;

    /// Compact struct to make two swaps (PancakeSwap on BSC)
    /// A => B (using pair1) then B => asset (of Wrapper) (using pair2)
    struct swapInfo {
        address token;
        address pair1;
        address pair2;
    }

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Thrown when a call to Compound returned an error.
    /// @param errorCode The error code returned by Compound
    error CompoundERC4626__CompoundError(uint256 errorCode);

    /// @notice Thrown when the deposited assets doesnot return any shares.
    error CompoundERC4626_ZEROSHARES_Error();

    /// @notice Thrown when the redeems shares doesnot return any assets.
    error CompoundERC4626_ZEROASSETS_Error();

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------
    constructor(
        ERC20 asset_, // underlying
        ERC20 reward_, // comp token or other
        ICEther cEther_, // compound concept of a share
        address manager_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        reward = reward_;
        cEther = cEther_;
        comptroller = IComptroller(cEther.comptroller());
        manager = manager_;
    }

    /// -----------------------------------------------------------------------
    /// Compound liquidity mining
    /// -----------------------------------------------------------------------

    function setRoute(
        address token,
        address pair1,
        address pair2
    ) external {
        require(msg.sender == manager, "onlyOwner");
        SwapInfo = swapInfo(token, pair1, pair2);
        ERC20(reward).approve(SwapInfo.pair1, type(uint256).max); /// max approve
        ERC20(SwapInfo.token).approve(SwapInfo.pair2, type(uint256).max); /// max approve
    }

    /// @notice Claims liquidity mining rewards from Compound and performs low-lvl swap with instant reinvesting
    /// Calling harvest() claims COMP-Fork token through direct Pair swap for best control and lowest cost
    /// harvest() can be called by anybody. ideally this function should be adjusted per needs (e.g add fee for harvesting)
    function harvest() external {
        ICEther[] memory cTokens = new ICEther[](1);
        cTokens[0] = cEther;

        /// TODO: Setter for rewardType
        comptroller.claimReward(1, address(this));

        uint256 earned = ERC20(reward).balanceOf(address(this));
        address rewardToken = address(reward);

        /// If only one swap needed (high liquidity pair) - set swapInfo.token0/token/pair2 to 0x
        if (SwapInfo.token == address(asset)) {
            DexSwap.swap(
                earned, /// REWARDS amount to swap
                rewardToken, // from REWARD (because of liquidity)
                address(asset), /// to target underlying of this Vault ie USDC
                SwapInfo.pair1 /// pairToken (pool)
            );
            /// If two swaps needed
        } else {
            uint256 swapTokenAmount = DexSwap.swap(
                earned, /// REWARDS amount to swap
                rewardToken, /// fromToken REWARD
                SwapInfo.token, /// to intermediary token with high liquidity (no direct pools)
                SwapInfo.pair1 /// pairToken (pool)
            );

            DexSwap.swap(
                swapTokenAmount,
                SwapInfo.token, // from received BUSD (because of liquidity)
                address(asset), /// to target underlying of this Vault ie USDC
                SwapInfo.pair2 /// pairToken (pool)
            );
        }

        afterDeposit(asset.balanceOf(address(this)), 0);
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function beforeWithdraw(uint256 assets, uint256) internal override {
        // Withdraw the underlying tokens from the cEther.
        uint256 errorCode = cEther.redeemUnderlying(assets);
        if (errorCode != NO_ERROR) {
            revert CompoundERC4626__CompoundError(errorCode);
        }
    }

    function viewUnderlyingBalanceOf() internal view returns (uint256) {
        return
            cEther.balanceOf(address(this)).mulWadDown(
                cEther.exchangeRateStored()
            );
    }

    function afterDeposit(uint256 assets, uint256) internal override {
        WrappedNative(address(asset)).withdraw(assets);
        // mint tokens
        cEther.mint{value: assets}();
    }

    function deposit(address receiver)
        public
        payable
        returns (uint256 shares)
    {
        // Check for rounding error since we round down in previewDeposit.
        if ((shares = previewDeposit(msg.value)) == 0)
            revert CompoundERC4626_ZEROSHARES_Error();
        require((shares = previewDeposit(msg.value)) != 0, "ZERO_SHARES");

        WrappedNative(address(asset)).deposit{value: msg.value}();

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, msg.value, shares);

        afterDeposit(msg.value, shares);
    }

    /// Standard ERC4626 deposit can only accept ERC20
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
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
        if (comptroller.mintGuardianPaused(address(cEther))) return 0;
        return type(uint256).max;
    }

    /// @notice maximum amount of shares that can be minted.
    /// This is capped by the amount of assets the cEther can be
    /// supplied with.
    /// This is 0 if minting is paused on the cEther.
    function maxMint(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(address(cEther))) return 0;
        return type(uint256).max;
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

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        WrappedNative(address(asset)).deposit{value: assets}();
        asset.safeTransfer(receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        if ((assets = previewRedeem(shares)) == 0)
            revert CompoundERC4626_ZEROASSETS_Error();

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        WrappedNative(address(asset)).deposit{value: assets}();
        asset.safeTransfer(receiver, assets);
    }

    receive() external payable {}

    /// -----------------------------------------------------------------------
    /// ERC20 metadata generation
    /// -----------------------------------------------------------------------

    function _vaultName(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultName)
    {
        vaultName = string.concat("ERC4626-Wrapped Benqi - ", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultSymbol)
    {
        vaultSymbol = string.concat("bq46-", asset_.symbol());
    }
}
