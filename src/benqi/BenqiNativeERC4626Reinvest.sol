// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ICEther} from "./compound/ICEther.sol";
import {LibCompound} from "./compound/LibCompound.sol";
import {IComptroller} from "./compound/IComptroller.sol";

import {DexSwap} from "./utils/swapUtils.sol";
import {WrappedNative} from "./utils/wrappedNative.sol";

/// @title BenqiNativeERC4626Reinvest
/// @notice Custom implementation of yield-daddy Compound wrapper with flexible reinvesting logic
/// @notice Extended with payable function to accept native token transfer
/// @author ZeroPoint Labs
contract BenqiNativeERC4626Reinvest is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                            LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using LibCompound for ICEther;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a call to Compound returned an error.
    /// @param errorCode The error code returned by Compound
    error COMPOUND_ERROR(uint256 errorCode);

    /// @notice Thrown when the deposited assets doesnot return any shares.
    error COMPOUND_ERROR_ZEROSHARES();

    /// @notice Thrown when the redeems shares doesnot return any assets.
    error COMPOUND_ZEROASSETS_ERROR();

    // @notice Thrown when reinvested amounts are not enough.
    error MIN_AMOUNT_ERROR();

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant NO_ERROR = 0;

    /*//////////////////////////////////////////////////////////////
                        IMMUTABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice cEther token reference
    ICEther public immutable cEther;

    /// @notice The Compound comptroller contract
    IComptroller public immutable comptroller;

    /// @notice Access Control for harvest() route
    address public immutable manager;

    /// @notice The COMP-like token contract
    ERC20 public immutable reward;

    /// @notice Type of reward currently distributed by Benqi Vaults
    uint8 public rewardType;

    /// @notice Map rewardType to rewardToken
    mapping(uint8 => address) public rewardTokenMap;

    /// @notice Map rewardType to swap route
    mapping(uint8 => swapInfo) public swapInfoMap;

    /// @notice Pointer to swapInfo
    swapInfo public SwapInfo;

    /// Compact struct to make two swaps (PancakeSwap on BSC)
    /// A => B (using pair1) then B => asset (of Wrapper) (using pair2)
    struct swapInfo {
        address token;
        address pair1;
        address pair2;
    }

    WrappedNative public wavax;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @notice Constructs the BenqiNativeERC4626Reinvest contract
    /// @dev asset_ is the underlying token of the Vault
    /// @dev reward_ is the COMP-like token
    /// @dev cEther_ is the Compound concept of a share
    /// @dev manager_ is the address that can set swap routes
    constructor(
        ERC20 asset_,
        ERC20 reward_,
        ICEther cEther_,
        address manager_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        reward = reward_;
        cEther = cEther_;
        comptroller = IComptroller(cEther.comptroller());
        wavax = WrappedNative(address(asset_));
        manager = manager_;
    }

    /*//////////////////////////////////////////////////////////////
                                REWARDS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set swap routes for selling rewards
    /// @notice Set type of reward we are harvesting and selling
    /// @dev 0 = BenqiToken, 1 = AVAX
    /// @dev Setting wrong addresses here will revert harvest() calls
    function setRoute(
        uint8 rewardType_,
        address rewardToken_,
        address token_,
        address pair1_,
        address pair2_
    ) external {
        require(msg.sender == manager, "onlyOwner");
        swapInfoMap[rewardType_] = swapInfo(token_, pair1_, pair2_);
        rewardTokenMap[rewardType_] = rewardToken_;
    }

    /// @notice Claims liquidity mining rewards from Benqi and sends it to this Vault
    function harvest(uint8 rewardType_, uint256 minAmountOut_) external {
        swapInfo memory swapMap = swapInfoMap[rewardType_];
        address rewardToken = rewardTokenMap[rewardType_];
        ERC20 rewardToken_ = ERC20(rewardToken);

        comptroller.claimReward(rewardType_, address(this));
        uint256 earned = ERC20(rewardToken).balanceOf(address(this));
        uint256 reinvestAmount;
        /// If only one swap needed (high liquidity pair) - set swapInfo.token0/token/pair2 to 0x
        if (swapMap.token == address(asset)) {
            rewardToken_.approve(swapMap.pair1, earned);

            reinvestAmount = DexSwap.swap(
                earned, /// REWARDS amount to swap
                rewardToken, // from REWARD (because of liquidity)
                address(asset), /// to target underlying of this Vault ie USDC
                swapMap.pair1 /// pairToken (pool)
            );
            /// If two swaps needed
        } else {
            rewardToken_.approve(swapMap.pair1, earned);

            uint256 swapTokenAmount = DexSwap.swap(
                earned, /// REWARDS amount to swap
                rewardToken, /// fromToken REWARD
                swapMap.token, /// to intermediary token with high liquidity (no direct pools)
                swapMap.pair1 /// pairToken (pool)
            );

            ERC20(swapMap.token).approve(swapMap.pair2, swapTokenAmount);

            reinvestAmount = DexSwap.swap(
                swapTokenAmount,
                swapMap.token, // from received BUSD (because of liquidity)
                address(asset), /// to target underlying of this Vault ie USDC
                swapMap.pair2 /// pairToken (pool)
            );
        }
        if (reinvestAmount < minAmountOut_) {
            revert MIN_AMOUNT_ERROR();
        }
        afterDeposit(asset.balanceOf(address(this)), 0);
    }

    /// @notice Check how much rewards are available to claim, useful before harvest()
    function getRewardsAccrued(uint8 rewardType_)
        external
        view
        returns (uint256 amount)
    {
        amount = comptroller.rewardAccrued(rewardType_, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets_, uint256) internal override {
        // Withdraw the underlying tokens from the cEther.
        uint256 errorCode = cEther.redeemUnderlying(assets_);
        if (errorCode != NO_ERROR) {
            revert COMPOUND_ERROR(errorCode);
        }
    }

    function _viewUnderlyingBalanceOf() internal view returns (uint256) {
        return
            cEther.balanceOf(address(this)).mulWadDown(
                cEther.exchangeRateStored()
            );
    }

    /// @notice "Regular" ERC20 deposit for WAVAX
    function afterDeposit(uint256 assets_, uint256) internal override {
        wavax.withdraw(assets_);
        cEther.mint{value: assets_}();
    }

    /// @notice "Payable" afterDeposit for special case when we deposit native token
    function afterDeposit(uint256 avaxAmt_) internal {
        cEther.mint{value: avaxAmt_}();
    }

    /// @notice Accept native token (AVAX) for deposit. Non-ERC4626 function.
    function deposit(address receiver_)
        public
        payable
        returns (uint256 shares)
    {
        // Check for rounding error since we round down in previewDeposit.
        if ((shares = previewDeposit(msg.value)) == 0)
            revert COMPOUND_ERROR_ZEROSHARES();
        require((shares = previewDeposit(msg.value)) != 0, "ZERO_SHARES");

        _mint(receiver_, shares);

        emit Deposit(msg.sender, receiver_, msg.value, shares);

        afterDeposit(msg.value);
    }

    /// @notice Standard ERC4626 deposit can only accept ERC20
    function deposit(uint256 assets_, address receiver_)
        public
        override
        returns (uint256 shares)
    {
        require((shares = previewDeposit(assets_)) != 0, "ZERO_SHARES");

        asset.safeTransferFrom(msg.sender, address(this), assets_);

        _mint(receiver_, shares);

        emit Deposit(msg.sender, receiver_, assets_, shares);

        afterDeposit(assets_, shares);
    }

    /// @notice Total amount of the underlying asset that
    /// @notice is "managed" by Vault.
    function totalAssets() public view override returns (uint256) {
        return _viewUnderlyingBalanceOf();
    }

    /// @notice maximum amount of assets that can be deposited.
    /// @notice This is capped by the amount of assets the cEther can be
    /// @notice supplied with.
    /// @notice This is 0 if minting is paused on the cEther.
    function maxDeposit(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(address(cEther))) return 0;
        return type(uint256).max;
    }

    /// @notice maximum amount of shares that can be minted.
    /// @notice This is capped by the amount of assets the cEther can be
    /// @notice supplied with.
    /// @notice This is 0 if minting is paused on the cEther.
    function maxMint(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(address(cEther))) return 0;
        return type(uint256).max;
    }

    /// @notice Maximum amount of assets that can be withdrawn.
    /// @notice This is capped by the amount of cash available on the cEther,
    /// @notice if all assets are borrowed, a user can't withdraw from the vault.
    function maxWithdraw(address owner_)
        public
        view
        override
        returns (uint256)
    {
        uint256 cash = cEther.getCash();
        uint256 assetsBalance = convertToAssets(balanceOf[owner_]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    /// @notice Maximum amount of shares that can be redeemed.
    /// @notice This is capped by the amount of cash available on the cEther,
    /// @notice if all assets are borrowed, a user can't redeem from the vault.
    function maxRedeem(address owner_) public view override returns (uint256) {
        uint256 cash = cEther.getCash();
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner_];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    /// @notice withdraw assets of the owner.
    function withdraw(
        uint256 assets_,
        address receiver_,
        address owner_
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets_); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets_, shares);

        _burn(owner_, shares);

        emit Withdraw(msg.sender, receiver_, owner_, assets_, shares);

        /// @dev Output token is WAVAX, same as input token (consitency vs gas cost)
        wavax.deposit{value: assets_}();

        asset.safeTransfer(receiver_, assets_);
    }

    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) public override returns (uint256 assets) {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares_;
        }

        // Check for rounding error since we round down in previewRedeem.
        if ((assets = previewRedeem(shares_)) == 0)
            revert COMPOUND_ZEROASSETS_ERROR();

        beforeWithdraw(assets, shares_);

        _burn(owner_, shares_);

        emit Withdraw(msg.sender, receiver_, owner_, assets, shares_);

        /// @dev Output token is WAVAX, same as input token (consitency vs gas cost)
        wavax.deposit{value: assets}();

        asset.safeTransfer(receiver_, assets);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                      ERC20 METADATA
    //////////////////////////////////////////////////////////////*/

    function _vaultName(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultName)
    {
        vaultName = string.concat("ERC4626-Wrapped Benqi -", asset_.symbol());
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
