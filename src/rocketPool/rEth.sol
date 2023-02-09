// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IWETH} from "./interfaces/IWETH.sol";
import {IRETH} from "./interfaces/IReth.sol";
import {IRSTORAGE} from "./interfaces/IRstorage.sol";
import {IRPROTOCOL} from "./interfaces/IRProtocol.sol";
import {IRETHTOKEN} from "./interfaces/IRethToken.sol";

import "forge-std/console.sol";

/// @notice RocketPool's rETH ERC4626 Wrapper
/// @author ZeroPoint Labs
contract rEthERC4626 is ERC4626 {
    bytes32 public immutable DEPOSIT_POOL =
        keccak256(abi.encodePacked("contract.address", "rocketDepositPool"));

    IWETH public weth;
    IRETH public rEth;
    IRSTORAGE public rStorage;
    IRPROTOCOL public rProtocol;
    IRETHTOKEN public rEthToken;
    ERC20 public rEthAsset;

    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    /// @param weth_ weth address (Vault's underlying / deposit token)
    /// @param rStorage_ rocketPool Storage contract address to read current implementation details
    constructor(address weth_, address rStorage_)
        ERC4626(ERC20(weth_), "ERC4626-Wrapped rEth", "wLstReth")
    {
        /// NOTE: Non-upgradable contract
        rStorage = IRSTORAGE(rStorage_);
        weth = IWETH(weth_);

        /// Get address of Deposit pool from address of rStorage on deployment
        /// NOTE: Upgradable contract
        address rocketDepositPoolAddress = _rocketDepositPoolAddress();
        address rocketProtocolAddress = _rocketProtocolAddress();
        console.log("rocketDepositPoolAddress", rocketDepositPoolAddress);
        console.log("rocketProtocolAddress", rocketProtocolAddress);
        rEth = IRETH(rocketDepositPoolAddress);
        rProtocol = IRPROTOCOL(rocketProtocolAddress);

        /// Get address of rETH ERC20 token
        /// NOTE: Non-upgradable contract
        address rocketTokenRETHAddress = rStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        );
        console.log("rocketTokenRETHAddress", rocketTokenRETHAddress);

        /// @dev Workaround for solmate's safeTransferLib
        rEthToken = IRETHTOKEN(rocketTokenRETHAddress);
        rEthAsset = ERC20(rocketTokenRETHAddress);
    }

    receive() external payable {}

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    /// @notice Deposit into active RocketDepositPool. Standard ERC4626 deposit can only accept ERC20
    /// @return shares - rEth as both Vault's shares and underlying
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {   

        /// @dev Call to check if rEth address didn't change
        if (rEth != IRETH(rStorage.getAddress(DEPOSIT_POOL))) {
            rEth = IRETH(rStorage.getAddress(DEPOSIT_POOL));
        }

        /// @dev Call to check if there are free slots to stake in the pool
        console.log("freeSlots", freeSlots());
        require(freeSlots() > assets, "NO_FREE_SLOTS");

        /// @dev previewDeposit needs to return amount of rEth minted from assets
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        console.log("deposit shares", shares);

        /// @dev Transfer weth to this contract
        asset.safeTransferFrom(msg.sender, address(this), assets);

        /// @dev Unwrap weth to eth
        weth.withdraw(assets);
        
        /// @dev We need to check how much rEth we have before deposit
        uint256 startBalance = rEthAsset.balanceOf(address(this));

        /// @dev Deposit eth to rocket pool
        rEth.deposit{value: assets}();

        /// @dev How much rEth are we receiving after deposit to the rocket pool
        /// TODO: balanceOf could be manipulated
        uint256 depositBalance = rEthAsset.balanceOf(address(this));
        uint256 rEthReceived = depositBalance - startBalance;
        
        console.log("rEthReceived", rEthReceived);

        /// @dev Should receive at least amount equal to the shares calculated
        require(rEthReceived == shares, "NOT_ENOUGH_rETH");

        _mint(receiver, rEthReceived);

        emit Deposit(msg.sender, receiver, assets, rEthReceived);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {   
        /// @dev Call to check if rEth address didn't change
        if (rEth != IRETH(rStorage.getAddress(DEPOSIT_POOL))) {
            rEth = IRETH(rStorage.getAddress(DEPOSIT_POOL));
        }

        /// get X rEth shares for Y eth assets
        assets = previewMint(shares);

        /// @dev Call to check if there are free slots to stake in the pool
        require(freeSlots() > assets, "NO_FREE_SLOTS");

        /// transfer Y eth asset to this contract
        asset.safeTransferFrom(msg.sender, address(this), assets);

        /// @dev Unwrap weth to eth
        weth.withdraw(assets);

        /// @dev We need to check how much rEth we have before deposit
        uint256 startBalance = rEthAsset.balanceOf(address(this));

        /// @dev Deposit eth to rocket pool
        rEth.deposit{value: assets}();

        /// @dev How much rEth are we receiving after deposit to the rocket pool
        /// TODO: balanceOf could be manipulated
        uint256 depositBalance = rEthAsset.balanceOf(address(this));
        uint256 rEthReceived = depositBalance - startBalance;

        console.log("rEthReceived", rEthReceived);
        console.log("shares", shares);
        
        /// @dev Should receive at least amount equal to the shares calculated
        // require(rEthReceived == assets, "NOT_ENOUGH_rETH");

        _mint(receiver, rEthReceived);

        emit Deposit(msg.sender, receiver, assets, rEthReceived);

    }

    /// @notice Withdraw function in this implementation allows to receive rEth, not redeem to eth
    /// @dev assets are equal to the shares in this case
    /// caller is asking for how much of rETH (asset) to withdraw, where asset is virtually eq to ETH
    /// rocket pool has no redeem-to-eth function
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {

        shares = previewWithdraw(assets);

        require(maxWithdraw(owner) >= assets, "MAX_WITHDRAW_EXCEEDED");

        console.log("shares withdraw", shares);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        console.log(
            "rEth balance withdraw",
            rEthAsset.balanceOf(address(this))
        );

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        console.log("withdraw assets", assets);
        rEthAsset.safeTransfer(receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        require(maxWithdraw(owner) >= assets, "MAX_WITHDRAW_EXCEEDED");

        console.log("redeemAssets", assets);
        console.log("redeemShares", shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        rEthAsset.safeTransfer(receiver, assets);
    }

    /// rEth as AUM. Non-rebasing!
    function totalAssets() public view virtual override returns (uint256) {
        return rEthAsset.balanceOf(address(this));
    }

    /// @notice Get amount of rEth from ETH
    function previewDeposit(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        return convertToShares(assets);
    }

    /// @notice Get amount of rEth from ETH
    function convertToShares(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        /// https://github.com/rocket-pool/rocketpool/blob/967e4d3c32721a84694921751920af313d1467af/contracts/interface/token/RocketTokenRETHInterface.sol#L9
        /// https://github.com/rocket-pool/rocketpool/blob/967e4d3c32721a84694921751920af313d1467af/contracts/contract/deposit/RocketDepositPool.sol#L82
        uint256 depositFee = assets.mulDivUp(rProtocol.getDepositFee(), 1e18); /// rEth.calcBase()
        uint256 depositNet = assets - depositFee;
        return rEthToken.getRethValue(depositNet);
    }

    /// @notice Get amount of ETH from rEth
    /// to get X rEth shares you need to supply Y eth assets
    function previewMint(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        /// https://github.com/rocket-pool/rocketpool/blob/967e4d3c32721a84694921751920af313d1467af/contracts/interface/token/RocketTokenRETHInterface.sol#L8
        // uint256 ethValue = rEthToken.getRethValue(shares);
        return rEthToken.getEthValue(shares) + 1;
        // return rEthToken.getRethValue(shares);
    }

    /// @notice Get (virtual) amount of ETH from burned rEth. caller receives rEth.
    function previewWithdraw(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        /// https://github.com/rocket-pool/rocketpool/blob/967e4d3c32721a84694921751920af313d1467af/contracts/interface/token/RocketTokenRETHInterface.sol#L9
        /// https://github.com/rocket-pool/rocketpool/blob/967e4d3c32721a84694921751920af313d1467af/contracts/contract/deposit/RocketDepositPool.sol#L82
        return rEthToken.getRethValue(assets);
    }

    /// @notice Get amount of ETH from rEth
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    /// @notice Get amount of ETH from rEth
    function convertToAssets(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        /// https://github.com/rocket-pool/rocketpool/blob/967e4d3c32721a84694921751920af313d1467af/contracts/interface/token/RocketTokenRETHInterface.sol#L8
        // uint256 ethValue = rEthToken.getRethValue(shares);
        return rEthToken.getEthValue(shares) + 1;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return balanceOf[owner];
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf[owner];
    }

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
