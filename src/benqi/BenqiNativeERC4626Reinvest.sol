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

/// @title BenqiERC4626Reinvest - Custom implementation of yield-daddy Compound wrapper with flexible reinvesting logic
/// @notice Extended with payable function to accept native token transfer
/// @author ZeroPoint Labs
contract BenqiNativeERC4626Reinvest is ERC4626 {
    /*//////////////////////////////////////////////////////////////
     Libraries usage
    //////////////////////////////////////////////////////////////*/

    using LibCompound for ICEther;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
     Constants
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant NO_ERROR = 0;

    /*//////////////////////////////////////////////////////////////
     Immutable params
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
     Errors
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a call to Compound returned an error.
    /// @param errorCode The error code returned by Compound
    error CompoundERC4626__CompoundError(uint256 errorCode);

    /// @notice Thrown when the deposited assets doesnot return any shares.
    error CompoundERC4626_ZEROSHARES_Error();

    /// @notice Thrown when the redeems shares doesnot return any assets.
    error CompoundERC4626_ZEROASSETS_Error();

    // @notice Thrown when reinvested amounts are not enough.
    error MIN_AMOUNT_ERROR();

    /*//////////////////////////////////////////////////////////////
     Constructor
    //////////////////////////////////////////////////////////////*/
    constructor(
        ERC20 asset_, // underlying
        ERC20 reward_, // comp token or other
        ICEther cEther_, // compound concept of a share
        address manager_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        reward = reward_;
        cEther = cEther_;
        comptroller = IComptroller(cEther.comptroller());
        wavax = WrappedNative(address(asset_));
        manager = manager_;
    }

    /*//////////////////////////////////////////////////////////////
     Compound liquidity mining
    //////////////////////////////////////////////////////////////*/

    /// @notice Set swap routes for selling rewards
    /// @notice Set type of reward we are harvesting and selling
    /// @dev 0 = BenqiToken, 1 = AVAX
    /// @dev Setting wrong addresses here will revert harvest() calls
    function setRoute(
        uint8 rewardType_,
        address rewardToken,
        address token,
        address pair1,
        address pair2
    ) external {
        require(msg.sender == manager, "onlyOwner");
        swapInfoMap[rewardType_] = swapInfo(token, pair1, pair2);
        rewardTokenMap[rewardType_] = rewardToken;
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
     ERC4626 overrides
    //////////////////////////////////////////////////////////////*/

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

    /// @notice "Regular" ERC20 deposit for WAVAX
    function afterDeposit(uint256 assets, uint256) internal override {
        wavax.withdraw(assets);
        cEther.mint{value: assets}();
    }

    /// @notice "Payable" afterDeposit for special case when we deposit native token
    function afterDeposit(uint256 avaxAmt) internal {
        cEther.mint{value: avaxAmt}();
    }

    /// @notice Accept native token (AVAX) for deposit. Non-ERC4626 function.
    function deposit(address receiver) public payable returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        if ((shares = previewDeposit(msg.value)) == 0)
            revert CompoundERC4626_ZEROSHARES_Error();
        require((shares = previewDeposit(msg.value)) != 0, "ZERO_SHARES");

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, msg.value, shares);

        afterDeposit(msg.value);
    }

    /// @notice Standard ERC4626 deposit can only accept ERC20
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

        /// @dev Output token is WAVAX, same as input token (consitency vs gas cost)
        wavax.deposit{value: assets}();

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

        /// @dev Output token is WAVAX, same as input token (consitency vs gas cost)
        wavax.deposit{value: assets}();

        asset.safeTransfer(receiver, assets);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
     ERC20 metadata generation
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
