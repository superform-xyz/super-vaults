// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {AaveV3ERC4626Reinvest} from "../AaveV3ERC4626Reinvest.sol";
import {AaveV3ERC4626ReinvestFactory} from "../AaveV3ERC4626ReinvestFactory.sol";
import {IRewardsController} from "../../aave-v3/external/IRewardsController.sol";
import {IPool} from "../external/IPool.sol";

contract AaveV3ERC4626ReinvestTest is Test {

    address public constant rewardRecipient = address(0x011);

    ////////////////////////////////////////

    address public manager;
    address public alice;
    address public bob;

    uint256 public ethFork;
    uint256 public ftmFork;
    uint256 public avaxFork;
    uint256 public polyFork;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");
    string FTM_RPC_URL = vm.envString("FTM_MAINNET_RPC");
    string AVAX_RPC_URL = vm.envString("AVAX_MAINNET_RPC");
    string POLYGON_MAINNET_RPC = vm.envString("POLYGON_MAINNET_RPC");

    AaveV3ERC4626Reinvest public vault;
    AaveV3ERC4626ReinvestFactory public factory;

    ERC20 public asset;
    ERC20 public aToken;
    IRewardsController public rewards;
    IPool public lendingPool;
    address public rewardToken;

    ////////////////////////////////////////

    constructor() {

        ethFork = vm.createFork(POLYGON_MAINNET_RPC); /// @dev No rewards on ETH mainnet
        ftmFork = vm.createFork(POLYGON_MAINNET_RPC);  /// @dev No rewards on FTM
        polyFork = vm.createFork(POLYGON_MAINNET_RPC); /// @dev No rewards on Polygon

        /// @dev REWARDS on Avax
        avaxFork = vm.createFork(POLYGON_MAINNET_RPC);

        manager = msg.sender;

        vm.selectFork(avaxFork);

        rewards = IRewardsController(vm.envAddress("AAVEV2_POLYGON_REWARDS"));
        lendingPool = IPool(vm.envAddress("AAVEV2_POLYGON_LENDINGPOOL"));

        factory = new AaveV3ERC4626ReinvestFactory(
            lendingPool,
            rewards,
            manager
        );

        (ERC4626 v, AaveV3ERC4626Reinvest v_) = setVault(
            ERC20(vm.envAddress("AAVEV2_POLYGON_DAI"))
        );
        vault = v_;
    }

    function setVault(
        ERC20 _asset
    ) public returns (ERC4626 vault_, AaveV3ERC4626Reinvest _vault_) {
        asset = _asset;

        /// @dev If we need strict ERC4626 interface
        vault_ = factory.createERC4626(asset);

        /// @dev If we need to use the AaveV2ERC4626Reinvest interface with harvest
        _vault_ = AaveV3ERC4626Reinvest(address(vault_));
    }


    function setUp() public {
        alice = address(0x1);
        bob = address(0x2);
        deal(address(asset), alice, 10000 ether);
        deal(address(asset), bob, 10000 ether);
    }
}