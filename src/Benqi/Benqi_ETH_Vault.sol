// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
// import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IRewardsCore} from "../interfaces/IRewardsCore.sol";

abstract contract CToken is ERC20 {
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
    function underlying() external view virtual returns (address);
    function redeemUnderlying(uint256) external virtual returns (uint256);
    function mint(uint256) external virtual returns (uint256);
    
    function exchangeRateStored() external virtual view returns (uint);
}

interface Unitroller {
    function mintGuardianPaused(address cToken)
        external
        view
        returns (bool);
    function supplyCaps(address cTokenAddress) external view returns(uint256);
    function claimReward(uint8 rewardType, address payable holder) external;
}

contract BenqiEthVault is ERC4626 {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /// @notice CToken token reference
    CToken public immutable cToken;

    /// @notice reference to the Unitroller of the CToken token
    Unitroller public immutable unitroller;

    /// @notice The address of the underlying ERC20 token used for
    /// the Vault for accounting, depositing, and withdrawing.
    ERC20 public immutable cTokenUnderlying;

    IRewardsCore public rewardsCore;

    /// @notice CompoundERC4626 constructor
    /// @param _cToken Compound cToken to wrap
    /// @param name ERC20 name of the vault shares token
    /// @param symbol ERC20 symbol of the vault shares token
    constructor(
        address _cToken,
        string memory name,
        string memory symbol,
        address _rewardsCore
    ) ERC4626(ERC20(CToken(_cToken).underlying()), name, symbol) {
        cToken = CToken(_cToken);
        unitroller = Unitroller(cToken.comptroller());
        cTokenUnderlying = ERC20(CToken(cToken).underlying());
        rewardsCore = IRewardsCore(_rewardsCore);
    }

    function beforeWithdraw(uint256 underlyingAmount, uint256)
        internal
        override
    {
        // Withdraw the underlying tokens from the cToken.
        require(
            cToken.redeemUnderlying(underlyingAmount) == 0,
            "REDEEM_FAILED"
        );
        
    }

    function viewUnderlyingBalanceOf() internal view returns (uint256) {
        return cToken.balanceOf(address(this)).mulWadDown(cToken.exchangeRateStored());
    }

    function afterDeposit(uint256 underlyingAmount, uint256) internal override {
        // Approve the underlying tokens to the cToken
        asset.safeApprove(address(cToken), underlyingAmount);

        // mint tokens
        require(cToken.mint(underlyingAmount) == 0, "MINT_FAILED");
    }

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    function totalAssets() public view override returns (uint256) {
        return viewUnderlyingBalanceOf();
    }

    /// @notice maximum amount of assets that can be deposited.
    /// This is capped by the amount of assets the cToken can be
    /// supplied with.
    /// This is 0 if minting is paused on the cToken.
    function maxDeposit(address) public view override returns (uint256) {
        address cTokenAddress = address(cToken);

        if (unitroller.mintGuardianPaused(cTokenAddress)) return 0;

        uint256 supplyCap = unitroller.supplyCaps(cTokenAddress);
        if (supplyCap == 0) return type(uint256).max;

        uint256 assetsDeposited = cToken.totalSupply().mulWadDown(
            cToken.exchangeRateStored()
        );
        return supplyCap - assetsDeposited;
    }

    /// @notice maximum amount of shares that can be minted.
    /// This is capped by the amount of assets the cToken can be
    /// supplied with.
    /// This is 0 if minting is paused on the cToken.
    function maxMint(address) public view override returns (uint256) {
        address cTokenAddress = address(cToken);

        if (unitroller.mintGuardianPaused(cTokenAddress)) return 0;

        uint256 supplyCap = unitroller.supplyCaps(cTokenAddress);
        if (supplyCap == 0) return type(uint256).max;

        uint256 assetsDeposited = cToken.totalSupply().mulWadDown(
            cToken.exchangeRateStored()
        );
        return convertToShares(supplyCap - assetsDeposited);
    }

    /// @notice Maximum amount of assets that can be withdrawn.
    /// This is capped by the amount of cash available on the cToken,
    /// if all assets are borrowed, a user can't withdraw from the vault.
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 cash = cToken.getCash();
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    /// @notice Maximum amount of shares that can be redeemed.
    /// This is capped by the amount of cash available on the cToken,
    /// if all assets are borrowed, a user can't redeem from the vault.
    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 cash = cToken.getCash();
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    function claimRewards() external {
        rewardsCore.claimRewards();
    }

    function withdrawTokens(address tokenAddress, uint256 amount) external {
        require(msg.sender == address(rewardsCore));
        if (tokenAddress != address(0)) {
            ERC20 token = ERC20(tokenAddress);
            uint tokenRemaining = token.balanceOf(address(this));
            if (amount > 0 && amount <= tokenRemaining) {
                token.transfer(msg.sender, amount);
            }
        } else if (tokenAddress == address(0)) {
            uint avaxRemaining = address(this).balance;
            if (amount > 0 && amount <= avaxRemaining) {
                (bool success, ) = msg.sender.call{value : amount}("");
                require(success, "Transfer failed.");
            }
        }
    }

    receive() external payable {}
}
