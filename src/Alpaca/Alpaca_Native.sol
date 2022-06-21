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
import {WrappedNative} from "../interfaces/WrappedNative.sol";
 
interface IBToken {
    function deposit(uint256) external payable;
    function totalToken() external view returns (uint256);
    function config() external view returns (address);
    function token() external view returns (address);
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
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

contract AlpacaNativeVault is ERC4626, Ownable {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /// @notice CToken token reference
    IBToken public immutable ibToken;

    IFairLaunch public staking;
    uint256 blah;
    /// @notice The address of the underlying ERC20 token used for
    /// the Vault for accounting, depositing, and withdrawing.
    ERC20 public immutable ibTokenUnderlying;

    uint256 public poolId;
    event RewardsClaimed(address admin, uint256 rewardsAmount);
    

    /// @notice CompoundERC4626 constructor
    /// @param _ibToken Compound cToken to wrap
    /// @param name ERC20 name of the vault shares token
    /// @param symbol ERC20 symbol of the vault shares token
    constructor(
        address _ibToken,
        string memory name,
        string memory symbol,
        address _staking,
        uint256 _pid
    ) ERC4626(ERC20(IBToken(_ibToken).token()), name, symbol) {
        ibToken = IBToken(_ibToken);
        ibTokenUnderlying = ERC20(ibToken.token());
        staking = IFairLaunch(_staking);
        poolId = _pid;
    }

    function beforeWithdraw(uint256 underlyingAmount, uint256)
        internal
        override
    {
        // convert asset token amount to ibtokens for withdrawal
        uint256 sharesToWithdraw = underlyingAmount * ERC20(address(ibToken)).totalSupply() / ibToken.totalToken();

        // Withdraw the underlying tokens from the cToken.
        unstake(sharesToWithdraw);
        ibToken.withdraw(blah);
        
    }

    function unstake(uint256 _ibTokenAmount) internal {
        staking.withdraw(address(this), poolId, _ibTokenAmount);
    }

    function viewUnderlyingBalanceOf() internal view returns (uint256) {
        IFairLaunch._userInfo memory depositDetails = staking.userInfo(poolId,address(this));
        console.log(depositDetails.rewardDebt, "fundedby");
        return depositDetails.amount.mulDivUp(ibToken.totalToken(),ERC20(address(ibToken)).totalSupply());
    }

    function afterDeposit(uint256 underlyingAmount, uint256) internal override {
        // Approve the underlying tokens to the cToken
        asset.safeApprove(address(ibToken), underlyingAmount);
        uint256 prevBalance = ERC20(address(ibToken)).balanceOf(address(this));
        ibToken.deposit(underlyingAmount);
        blah = ibToken.balanceOf(address(this));
        // mint ibtokens tokens
        require(ibToken.balanceOf(address(this)) > prevBalance, "MINT_FAILED");
        stake();
    }

    function depositNative(address receiver) public payable returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(msg.value)) != 0, "ZERO_SHARES");

        WrappedNative(address(asset)).deposit{value: msg.value}();
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, msg.value, shares);

        afterDeposit(msg.value, shares);
    }

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

    function stake() internal {
        // Approve the underlying tokens to the cToken
        ERC20(address(ibToken)).approve(address(staking), type(uint256).max);
        staking.deposit(address(this), poolId, ERC20(address(ibToken)).balanceOf(address(this)));
    }
    

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    function totalAssets() public view override returns (uint256) {
        return viewUnderlyingBalanceOf();
    }


    function claimRewards() external onlyOwner() {
        uint256 rewards = ERC20(staking.alpaca()).balanceOf(address(this));
        ERC20(staking.alpaca()).safeTransfer(msg.sender, rewards);
        emit RewardsClaimed(msg.sender, rewards);
    }

    receive() external payable {}
}
