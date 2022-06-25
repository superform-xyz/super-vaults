// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
// import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IRewardsCore} from "../interfaces/IRewardsCore.sol";
//import "../../node_modules/hardhat/console.sol";
import "forge-std/console.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {DexSwap} from "../utils/swapUtils.sol";

interface IBToken {
    function deposit(uint256) external payable;
    function totalToken() external view returns (uint256);
    function config() external view returns (address);
    function token() external view returns (address);
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function reservePool() external view returns (uint256);
    function vaultDebtVal() external view returns (uint256);
    function lastAccrueTime() external view returns (uint256);
    function pendingInterest(uint256 value) external view returns (uint256);
}

interface IVaultConfig {
  /// @dev Return the bps rate for reserve pool.
  function getReservePoolBps() external view returns (uint256);
}

interface IFairLaunch {
    function alpacaPerBlock() external view returns (uint256);
    function pendingAlpaca(uint256 _pid,uint256 _user) external returns (uint256);
    struct _poolInfo {
        address stakeToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accAlpacaPerShare;
        uint256 accAlpacaPerShareTilBonusEnd;
    }
    struct _userInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 bonusDebt;
        address fundedBy;
    }
    function poolInfo(uint256 _pid) external returns ( _poolInfo memory);
    function userInfo(uint256, address) external view returns(_userInfo memory);
    function deposit(address user, uint256 pid, uint256 amount) external;
    function harvest(uint256 pid) external;
    function withdraw(address _for,uint256 _pid,uint256 _amount) external;
    function alpaca() external view returns (address);
}

contract AlpacaBTCVault is ERC4626, Ownable {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    //busd in this case as it has the most liquidity for alpaca when compared to alpaca/BNB
    ERC20 public swapReceipentToken;

    /// @notice CToken token reference
    IBToken public immutable ibToken;

    IFairLaunch public staking;
    /// @notice The address of the underlying ERC20 token used for
    /// the Vault for accounting, depositing, and withdrawing.
    ERC20 public immutable ibTokenUnderlying;

    uint256 public poolId;
    uint256 public lastHarvestBlock = 0;

    address private depositTokenSwap;
    address private rewardTokenSwap;

    event RewardsReinvested(address user, uint256 reinvestAmount);
    

    /// @notice CompoundERC4626 constructor
    /// @param _ibToken Compound cToken to wrap
    /// @param name ERC20 name of the vault shares token
    /// @param symbol ERC20 symbol of the vault shares token
    constructor(
        address _ibToken,
        string memory name,
        string memory symbol,
        address _staking,
        uint256 _pid,
        address _swapReceipentToken,
        address _rewardTokenSwap,
        address _depositTokenSwap
    ) ERC4626(ERC20(IBToken(_ibToken).token()), name, symbol) {
        ibToken = IBToken(_ibToken);
        ibTokenUnderlying = ERC20(ibToken.token());
        staking = IFairLaunch(_staking);
        poolId = _pid;
        swapReceipentToken = ERC20(_swapReceipentToken);
        rewardTokenSwap = _rewardTokenSwap;
        depositTokenSwap = _depositTokenSwap;
    }

    function beforeWithdraw(uint256 underlyingAmount, uint256 sharesAmount)
        internal
        override
    {
        // convert asset token amount to ibtokens for withdrawal
        uint256 sharesToWithdraw = underlyingAmount.mulDivDown(ERC20(address(ibToken)).totalSupply(),alpacaVaultTotalToken());

        // Withdraw the underlying tokens from the cToken.
        unstake(sharesToWithdraw);
        ibToken.withdraw(sharesToWithdraw);
        
    }

    function unstake(uint256 _ibTokenAmount) internal {
        staking.withdraw(address(this), poolId, _ibTokenAmount);
    }

    function viewUnderlyingBalanceOf() internal view returns (uint256) {
        IFairLaunch._userInfo memory depositDetails = staking.userInfo(poolId,address(this));
        return depositDetails.amount.mulDivUp(alpacaVaultTotalToken(),ERC20(address(ibToken)).totalSupply());
    }

    function afterDeposit(uint256 underlyingAmount, uint256) internal override {
        // Approve the underlying tokens to the cToken
        asset.safeApprove(address(ibToken), underlyingAmount);
        uint256 prevBalance = ERC20(address(ibToken)).balanceOf(address(this));
        ibToken.deposit(underlyingAmount);
        // mint ibtokens tokens
        require(ibToken.balanceOf(address(this)) > prevBalance, "MINT_FAILED");
        stake();
    }

    function stake() internal {
        // Approve the underlying tokens to the cToken
        ERC20(address(ibToken)).approve(address(staking), type(uint256).max);
        staking.deposit(address(this), poolId, ERC20(address(ibToken)).balanceOf(address(this)));
    }

    function alpacaVaultTotalToken() public view returns (uint256) {
        uint256 reservePool = ibToken.reservePool();
        uint256 vaultDebtVal = ibToken.vaultDebtVal();
        if (block.timestamp > ibToken.lastAccrueTime()) {
            uint256 interest = ibToken.pendingInterest(0);
            uint256 toReserve = interest.mulDivDown(IVaultConfig(ibToken.config()).getReservePoolBps(),10000);
            reservePool = reservePool + (toReserve);
            vaultDebtVal = vaultDebtVal + (interest);
        }
        return asset.balanceOf(address(ibToken)) + (vaultDebtVal) - (reservePool);
    }
    

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    function totalAssets() public view override returns (uint256) {
        return viewUnderlyingBalanceOf();
    }


    function reinvest() external onlyOwner() {
         if (lastHarvestBlock == block.number) {
            return;
        }

        // Do not harvest if no token is deposited (otherwise, fairLaunch will fail)
        if (viewUnderlyingBalanceOf() == 0) {
            return;
        }

        // Collect alpacaToken
        staking.harvest(poolId);

        uint256 earnedAlpacaBalance = ERC20(staking.alpaca()).balanceOf(address(this));
        console.log(earnedAlpacaBalance, "Alpaca Balance");
        if (earnedAlpacaBalance == 0) {
            return;
        }
        if (staking.alpaca() != address(ibTokenUnderlying)) {
            uint256 swapTokenAmount = DexSwap.swap(earnedAlpacaBalance, address(ibTokenUnderlying), address(swapReceipentToken), rewardTokenSwap);
            DexSwap.swap(swapTokenAmount, address(swapReceipentToken), address(asset), depositTokenSwap);
        }
        uint256 reinvestAmount = asset.balanceOf(address(this));
        afterDeposit(reinvestAmount, 0);
        lastHarvestBlock = block.number;
        emit RewardsReinvested(msg.sender, reinvestAmount);
    }
}
