// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IWETH} from "./interfaces/IWETH.sol";
import {IRETH} from "./interfaces/IReth.sol";
import {IRSTORAGE} from "./interfaces/IRstorage.sol";
import {IRPROTOCOL} from "./interfaces/IRProtocol.sol";
import {IRETHTOKEN} from "./interfaces/IRethToken.sol";

/// @title rEthERC4626
/// @notice Experimental RocketPool's rETH ERC4626 Wrapper
/// @notice Preview functions allow to check current value of held rETH tokens denominated as ETH
/// @notice Redemption is denominated in rETH as RocketPool doesn't allow to redeem ETH directly
/// @notice Adapter can be used as a good base for building rETH oriented strategy (requires changes to shares calculation)
/// @notice deposit & mint are "entry" functions to RocketPool - caller gives weth, caller receives wrEth, vault holds rEth
/// @notice withdraw & redeem are "exit" functions from rEthERC4626  - caller gives wrEth, caller receives rEth
/// @author ZeroPoint Labs
contract rEthERC4626 is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                        LIBRARIES USAGES
    //////////////////////////////////////////////////////////////*/

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Call to check if there are free slots to stake in the pool
    error NO_FREE_SLOTS();

    /// @notice Thrown when trying to deposit 0 assets
    error ZERO_ASSETS();

    /// @notice Thrown when trying to redeem with 0 tokens invested
    error ZERO_SHARES();

    /// @notice Thrown when rEthReceived is lower than shares
    error NOT_ENOUGH_RETH();

    /// @notice Thrown if max withdraw is exceeded
    error MAX_WITHDRAW_EXCEEDED();

    /// @notice Thrown if max redeem is exceeded
    error MAX_REDEEM_EXCEEDED();

    /*//////////////////////////////////////////////////////////////
                      IMMUATABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    bytes32 public immutable DEPOSIT_POOL =
        keccak256(abi.encodePacked("contract.address", "rocketDepositPool"));

    IWETH public weth;
    IRETH public rEth;
    IRSTORAGE public rStorage;
    IRPROTOCOL public rProtocol;
    IRETHTOKEN public rEthToken;
    ERC20 public rEthAsset;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param weth_ weth address (Vault's underlying / deposit token)
    /// @param rStorage_ rocketPool Storage contract address to read current implementation details
    constructor(address weth_, address rStorage_)
        ERC4626(ERC20(weth_), "ERC4626-Wrapped rEth", "wrEth")
    {
        /// NOTE: Non-upgradable contract
        rStorage = IRSTORAGE(rStorage_);
        weth = IWETH(weth_);

        /// Get address of Deposit pool from address of rStorage on deployment
        /// NOTE: Upgradable contract
        address rocketDepositPoolAddress = _rocketDepositPoolAddress();
        address rocketProtocolAddress = _rocketProtocolAddress();

        rEth = IRETH(rocketDepositPoolAddress);
        rProtocol = IRPROTOCOL(rocketProtocolAddress);

        /// Get address of rETH ERC20 token
        /// NOTE: Non-upgradable contract
        address rocketTokenRETHAddress = rStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        );

        /// @dev Workaround for solmate's safeTransferLib
        rEthToken = IRETHTOKEN(rocketTokenRETHAddress);
        rEthAsset = ERC20(rocketTokenRETHAddress);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into active RocketDepositPool. Standard ERC4626 deposit can only accept ERC20
    /// @return shares - rEth as both Vault's shares (wrEth) and underlying virtually backed by ETH
    /// @dev Deposit function obeys ERC4626 standard
    function deposit(uint256 assets_, address receiver_)
        public
        override
        returns (uint256 shares)
    {
        /// @dev Call to check if rEth address didn't change
        if (rEth != IRETH(rStorage.getAddress(DEPOSIT_POOL))) {
            rEth = IRETH(rStorage.getAddress(DEPOSIT_POOL));
        }

        /// @dev Call to check if there are free slots to stake in the pool
        if (freeSlots() <= assets_) revert NO_FREE_SLOTS();

        /// @dev previewDeposit needs to return amount of rEth minted from assets
        if ((shares = previewDeposit(assets_)) == 0) revert ZERO_SHARES();

        /// @dev Transfer weth to this contract
        asset.safeTransferFrom(msg.sender, address(this), assets_);

        /// @dev Unwrap weth to eth
        weth.withdraw(assets_);

        /// @dev We need to check how much rEth we have before deposit
        uint256 startBalance = rEthAsset.balanceOf(address(this));

        /// @dev Deposit eth to rocket pool
        rEth.deposit{value: assets_}();

        /// @dev How much rEth are we receiving after deposit to the rocket pool
        /// NOTE: Prone to inflation attack on balance of this contract!!!
        uint256 depositBalance = rEthAsset.balanceOf(address(this));
        uint256 rEthReceived = depositBalance - startBalance;

        /// @dev Should receive at least amount equal to the shares calculated
        if (rEthReceived != shares) revert NOT_ENOUGH_RETH();

        _mint(receiver_, rEthReceived);

        emit Deposit(msg.sender, receiver_, assets_, rEthReceived);
    }

    /// @notice Mint specified amount of rETH (shares) from provided ETH (asset)
    /// @return assets - rEth as both Vault's shares and underlying
    /// @dev Mint function obeys ERC4626 standard
    function mint(uint256 shares_, address receiver_)
        public
        override
        returns (uint256 assets)
    {
        /// @dev Call to check if rEth address didn't change
        if (rEth != IRETH(rStorage.getAddress(DEPOSIT_POOL))) {
            rEth = IRETH(rStorage.getAddress(DEPOSIT_POOL));
        }

        /// get X rEth shares for Y eth assets
        assets = previewMint(shares_);

        /// @dev Call to check if there are free slots to stake in the pool
        if (freeSlots() <= assets) revert NO_FREE_SLOTS();

        /// transfer Y eth asset to this contract
        asset.safeTransferFrom(msg.sender, address(this), assets);

        /// @dev Unwrap weth to eth
        weth.withdraw(assets);

        /// @dev We need to check how much rEth we have before deposit
        uint256 startBalance = rEthAsset.balanceOf(address(this));

        /// @dev Deposit eth to rocket pool
        rEth.deposit{value: assets}();

        /// @dev How much rEth are we receiving after deposit to the rocket pool
        /// NOTE: Prone to inflation attack on balance of this contract!!!
        uint256 depositBalance = rEthAsset.balanceOf(address(this));
        uint256 rEthReceived = depositBalance - startBalance;

        _mint(receiver_, rEthReceived);

        emit Deposit(msg.sender, receiver_, assets, rEthReceived);
    }

    /// @notice Withdraw in this implementation allows to receive rEth from wrEth, not redeem directly to ETH (from rEth)
    /// @notice caller is asking for asset rETH/wrEth to withdraw, where asset is virtually equal to ETH-backing
    /// @notice rocket pool has no redeem-to-eth function
    /// @dev To allow withdrawing "assets" as ETH, directly from rEth, would require an exchange of rEth to ETH on a DEX
    /// @dev That is considered an extension to the following implementation, which is strict ERC4626 wrapper over rEth token interface
    function withdraw(
        uint256 assets_,
        address receiver_,
        address owner_
    ) public override returns (uint256 shares) {
        /// @dev Returns
        shares = previewWithdraw(assets_);

        /// @dev Revert early, will fail on safeTransfer otherwise anyways
        if (maxWithdraw(owner_) < shares) revert MAX_WITHDRAW_EXCEEDED();

        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares;
        }

        _burn(owner_, shares);

        emit Withdraw(msg.sender, receiver_, owner_, assets_, shares);

        /// @dev Transfers amount of rEth equal to amount of ETH requested
        rEthAsset.safeTransfer(receiver_, shares);
    }

    /// @notice Redeem rETH for burning wrEth shares (of this vault)
    /// @notice caller is asking to redeem wrEth shares to rEth, exit asset is rEth
    /// @dev To allow redeeming "assets" as ETH, directly from rEth, would require an exchange of rEth to ETH on a DEX
    /// @dev That is considered an extension to the following implementation, which is strict ERC4626 wrapper over rEth token interface
    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) public override returns (uint256 assets) {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares_;
        }

        /// @dev return virtual amount of ETH backing rEth shares
        if ((assets = previewRedeem(shares_)) == 0) revert ZERO_ASSETS();

        if (maxRedeem(owner_) < shares_) revert MAX_REDEEM_EXCEEDED();

        _burn(owner_, shares_);

        emit Withdraw(msg.sender, receiver_, owner_, assets, shares_);

        /// @dev Transfers amount of the requested rEth shares. We can transfer "shares" in this impl because of 1:1 ratio rEth:wrEth
        rEthAsset.safeTransfer(receiver_, shares_);
    }

    /*//////////////////////////////////////////////////////////////

                            ACCOUNTING LOGIC

                Here, previewFunctions are wrappers around
                rocket pool getters. Only previewDeposit
                is used directly in the Vault's accounting
                Remaining functions return virtual amounts
                of ETH-backed or rEth-redeemable shares.

    //////////////////////////////////////////////////////////////*/

    /// @notice rEth token is used as AUM
    /// @dev NOTE: Mitigate inflation attack (transfering rETH to this contract)
    function totalAssets() public view virtual override returns (uint256) {
        return rEthAsset.balanceOf(address(this));
    }

    /// @notice Get amount of rEth from ETH
    /// @notice Calculated against RocketPool Deposit Pool with fee subtracted
    function previewDeposit(uint256 assets_)
        public
        view
        override
        returns (uint256)
    {
        return convertToShares(assets_);
    }

    /// @notice Get amount of rEth from ETH
    /// @notice Calculated against RocketPool Deposit Pool with fee subtracted
    function convertToShares(uint256 assets_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        /// https://github.com/rocket-pool/rocketpool/blob/967e4d3c32721a84694921751920af313d1467af/contracts/interface/token/RocketTokenRETHInterface.sol#L9
        /// https://github.com/rocket-pool/rocketpool/blob/967e4d3c32721a84694921751920af313d1467af/contracts/contract/deposit/RocketDepositPool.sol#L82
        uint256 depositFee = assets_.mulDivUp(rProtocol.getDepositFee(), 1e18); /// rEth.calcBase()
        uint256 depositNet = assets_ - depositFee;
        return rEthToken.getRethValue(depositNet);
    }

    /// @notice Get (virtual) amount of ETH-backing for provided rEth shares
    /// @notice to get X rEth shares you need to supply Y eth assets
    function previewMint(uint256 shares_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        /// https://github.com/rocket-pool/rocketpool/blob/967e4d3c32721a84694921751920af313d1467af/contracts/interface/token/RocketTokenRETHInterface.sol#L8
        return rEthToken.getEthValue(shares_) + 1;
    }

    /// @notice Get amount of rEth shares for provided ETH-backing
    function previewWithdraw(uint256 assets_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        /// https://github.com/rocket-pool/rocketpool/blob/967e4d3c32721a84694921751920af313d1467af/contracts/interface/token/RocketTokenRETHInterface.sol#L9
        /// https://github.com/rocket-pool/rocketpool/blob/967e4d3c32721a84694921751920af313d1467af/contracts/contract/deposit/RocketDepositPool.sol#L82
        return rEthToken.getRethValue(assets_);
    }

    /// @notice Get (virtual) amount of ETH-backing for provided rEth shares
    /// @dev Vault doesn't use this value internally as it only operates on rEth shares
    /// @dev Value can be used to calculate real value of rEth shares
    function previewRedeem(uint256 shares_)
        public
        view
        override
        returns (uint256)
    {
        return convertToAssets(shares_);
    }

    /// @notice Get (virtual) amount of ETH-backing for provided rEth shares
    function convertToAssets(uint256 shares_)
        public
        view
        virtual
        override
        returns (uint256)
    {
        /// https://github.com/rocket-pool/rocketpool/blob/967e4d3c32721a84694921751920af313d1467af/contracts/interface/token/RocketTokenRETHInterface.sol#L8
        return rEthToken.getEthValue(shares_) + 1;
    }

    /// @notice Max withdraw of rEth (wrEth shares)
    function maxWithdraw(address owner_)
        public
        view
        override
        returns (uint256)
    {
        return balanceOf[owner_];
    }

    /// @notice Max redeem of rEth (wrEth shares)
    function maxRedeem(address owner_) public view override returns (uint256) {
        return balanceOf[owner_];
    }

    /// @notice Max amount of ETH user will receive from his wrEth/rEth shares
    function maxRedeemable(address owner_)
        public
        view
        returns (uint256 ethBackedAmount)
    {
        uint256 balance = balanceOf[owner_];
        return previewRedeem(balance);
    }

    /*//////////////////////////////////////////////////////////////
                        ROCKET POOL CHECKS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if Rocket's Deposit Pool has free slots to stake
    function freeSlots() public view returns (uint256) {
        uint256 _freeSlots = rEth.getBalance();
        uint256 _poolSize = rProtocol.getMaximumDepositPoolSize();
        /// @dev make a check for negative case here (round to 0)
        return _poolSize - _freeSlots;
    }

    /// @notice Get address of active rEth contract (rocketDepositPool)
    function _rocketDepositPoolAddress() internal view returns (address) {
        return
            rStorage.getAddress(
                keccak256(
                    abi.encodePacked("contract.address", "rocketDepositPool")
                )
            );
    }

    /// @notice Get address of active rEth contract (rocketTokenRETH)
    function _rocketProtocolAddress() internal view returns (address) {
        return
            rStorage.getAddress(
                keccak256(
                    abi.encodePacked(
                        "contract.address",
                        "rocketDAOProtocolSettingsDeposit"
                    )
                )
            );
    }
}
