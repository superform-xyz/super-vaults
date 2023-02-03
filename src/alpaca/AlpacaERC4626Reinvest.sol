// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IBToken} from "./interfaces/IBToken.sol";
import {IFairLaunch} from "./interfaces/IFairLaunch.sol";
import {DexSwap} from "./utils/swapUtils.sol";

interface IVaultConfig {
    /// @dev Return the bps rate for reserve pool.
    function getReservePoolBps() external view returns (uint256);
}

contract AlpacaERC4626Reinvest is ERC4626 {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /// @notice CToken token reference
    IBToken public immutable ibToken;
    address public immutable manager;
    IFairLaunch public immutable staking;
    address public immutable alpacaToken;

    uint256 public poolId;

    /// @notice Pointer to swapInfo
    swapInfo public SwapInfo;

    error NotEnoughReinvestAmount_Error();

    /// Compact struct to make two swaps (PancakeSwap on BSC)
    /// A => B (using pair1) then B => asset (of BaseWrapper) (using pair2)
    /// will work fine as long we only get 1 type of reward token
    struct swapInfo {
        address token;
        address pair1;
        address pair2;
    }

    event RewardsReinvested(address user, uint256 reinvestAmount);

    /// @notice CompoundERC4626 constructor
    constructor(
        IBToken asset_, // ibToken, USDC > ibUSDC
        IFairLaunch staking_,
        uint256 poolId_
    )
        ERC4626(
            ERC20(asset_.token()),
            _vaultName(ERC20(asset_.token())),
            _vaultSymbol(ERC20(asset_.token()))
        )
    {
        ibToken = asset_;
        staking = staking_;
        poolId = poolId_;
        alpacaToken = staking.alpaca();
        manager = msg.sender;
        /// max approve to save gas
        ERC20(address(ibToken)).approve(address(staking_), type(uint256).max);
        /// We auto-stake anyways, save gas
        asset.safeApprove(address(ibToken), type(uint256).max);
    }

    function beforeWithdraw(uint256 underlyingAmount, uint256 sharesAmount)
        internal
        override
    {
        // convert asset token amount to ibtokens for withdrawal
        uint256 sharesToWithdraw = underlyingAmount.mulDivDown(
            ERC20(address(ibToken)).totalSupply(),
            alpacaVaultTotalToken()
        );

        // Withdraw the underlying tokens from the cToken.
        unstake(sharesToWithdraw);
        ibToken.withdraw(sharesToWithdraw);
    }

    function afterDeposit(uint256 underlyingAmount, uint256) internal override {
        ibToken.deposit(underlyingAmount);
        staking.deposit(
            address(this),
            poolId,
            ERC20(address(ibToken)).balanceOf(address(this))
        );
    }

    function setRoute(
        address token,
        address pair1,
        address pair2
    ) external {
        require(msg.sender == manager, "onlyOwner");
        SwapInfo = swapInfo(token, pair1, pair2);
        ERC20(alpacaToken).approve(SwapInfo.pair1, type(uint256).max); /// max approve
        ERC20(SwapInfo.token).approve(SwapInfo.pair2, type(uint256).max); /// max approve
    }

    function harvest(uint256 minAmountOut_) external {
        staking.harvest(poolId);

        uint256 earned = ERC20(alpacaToken).balanceOf(address(this));
        uint256 reinvestAmount;
        /// For ALPACA we use best liquidity pairs on Pancakeswap
        /// https://pancakeswap.finance/info/pools
        /// Only one swap needed, in this case - set swapInfo.token0/token/pair2 to 0x
        if (SwapInfo.token == address(asset)) {
            reinvestAmount = DexSwap.swap(
                earned, /// ALPACA amount to swap
                alpacaToken, // from ALPACA (because of liquidity)
                address(asset), /// to target underlying of BaseWrapper ie USDC
                SwapInfo.pair1 /// pairToken (pool)
                /// https://pancakeswap.finance/info/pool/0x2354ef4df11afacb85a5c7f98b624072eccddbb1
            );
            /// Two swaps needed
        } else {
            uint256 swapTokenAmount = DexSwap.swap(
                earned, /// ALPACA amount to swap
                alpacaToken, /// fromToken ALPACA
                SwapInfo.token, /// toToken ie BUSD (because of liquidity)
                SwapInfo.pair1 /// pairToken (pool)
                /// https://pancakeswap.finance/info/pool/0x7752e1fa9f3a2e860856458517008558deb989e3
            );

            reinvestAmount = DexSwap.swap(
                swapTokenAmount,
                SwapInfo.token, // from received BUSD (because of liquidity)
                address(asset), /// to target underlying of BaseWrapper USDC
                SwapInfo.pair2 /// pairToken (pool)
                /// https://pancakeswap.finance/info/pool/0x2354ef4df11afacb85a5c7f98b624072eccddbb1
            );
        }

        if (reinvestAmount < minAmountOut_) {
            revert NotEnoughReinvestAmount_Error();
        }
        afterDeposit(asset.balanceOf(address(this)), 0);
    }

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

        asset.safeTransfer(receiver, asset.balanceOf(address(this)));
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
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(
            msg.sender,
            receiver,
            owner,
            asset.balanceOf(address(this)),
            shares
        );

        asset.safeTransfer(receiver, asset.balanceOf(address(this)));
    }

    function unstake(uint256 _ibTokenAmount) internal {
        staking.withdraw(address(this), poolId, _ibTokenAmount);
    }

    function viewUnderlyingBalanceOf() internal view returns (uint256) {
        IFairLaunch._userInfo memory depositDetails = staking.userInfo(
            poolId,
            address(this)
        );
        return
            depositDetails.amount.mulDivUp(
                alpacaVaultTotalToken(),
                ERC20(address(ibToken)).totalSupply()
            );
    }

    function alpacaVaultTotalToken() public view returns (uint256) {
        uint256 reservePool = ibToken.reservePool();
        uint256 vaultDebtVal = ibToken.vaultDebtVal();
        if (block.timestamp > ibToken.lastAccrueTime()) {
            uint256 interest = ibToken.pendingInterest(0);
            uint256 toReserve = interest.mulDivDown(
                IVaultConfig(ibToken.config()).getReservePoolBps(),
                10000
            );
            reservePool = reservePool + (toReserve);
            vaultDebtVal = vaultDebtVal + (interest);
        }
        return
            asset.balanceOf(address(ibToken)) + (vaultDebtVal) - (reservePool);
    }

    /// @notice Total amount of the underlying asset that"managed" by Vault.
    function totalAssets() public view override returns (uint256) {
        return viewUnderlyingBalanceOf();
    }

    function _vaultName(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultName)
    {
        vaultName = string.concat("StratWrapper-4626 ", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultSymbol)
    {
        vaultSymbol = string.concat("w4626-", asset_.symbol());
    }
}
