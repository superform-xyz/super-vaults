// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {AaveV2StrategyWrapperNoHarvester} from "../aave-v2/AaveV2StrategyWrapperNoHarvester.sol";
import {AaveV2StrategyWrapperWithHarvester} from "../aave-v2/AaveV2StrategyWrapperWithHarvester.sol";
import {IMultiFeeDistribution} from "../utils/aave/IMultiFeeDistribution.sol";
import {ILendingPool} from "../utils/aave/ILendingPool.sol";

import {Harvester} from "../utils/harvest/Harvester.sol";

contract AaveV2HarvesterTest is Test {
    uint256 public ethFork;
    uint256 public ftmFork;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");
    string FTM_RPC_URL = vm.envString("FTM_MAINNET_RPC");

    AaveV2StrategyWrapperWithHarvester public vaultHarvester;

    Harvester public harvester;

    /// Fantom's Geist Forked AAVE-V2 Protocol DAI Pool Config
    ERC20 public underlying = ERC20(0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E); /// DAI
    ERC20 public aToken = ERC20(0x07E6332dD090D287d3489245038daF987955DCFB); // gDAI
    IMultiFeeDistribution public rewards =
        IMultiFeeDistribution(0x49c93a95dbcc9A6A4D8f77E59c038ce5020e82f8);
    ILendingPool public lendingPool =
        ILendingPool(0x9FAD24f572045c7869117160A571B2e50b10d068);
    address rewardToken = 0xd8321AA83Fb0a4ECd6348D4577431310A6E0814d;

    function setUp() public {
        ftmFork = vm.createFork(FTM_RPC_URL);
        address manager = msg.sender;
        vm.selectFork(ftmFork);

        vaultHarvester = new AaveV2StrategyWrapperWithHarvester(
            underlying,
            aToken,
            rewards,
            lendingPool,
            rewardToken,
            manager
        );

        harvester = new Harvester(
            manager
        );

        vm.startPrank(manager);
        vaultHarvester.enableHarvest(harvester);

        address swapToken = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83; /// FTM
        address swapPair1 = 0x668AE94D0870230AC007a01B471D02b2c94DDcB9; /// Geist - Ftm
        address swapPair2 = 0xe120ffBDA0d14f3Bb6d6053E90E63c572A66a428; /// Ftm - Dai
        
        harvester.setVault(vaultHarvester, ERC20(rewardToken));
        harvester.setRoute(swapToken, swapPair1, swapPair2);

        vm.stopPrank();
        /// Simulate rewards accrued to the vault contract
        deal(rewardToken, address(vaultHarvester), 1000 ether);
    }

    // function testWithHarvester() public {
    //     address alice = address(0x1cA60862a771f1F47d94F87bebE4226141b19C9c);
    //     vm.startPrank(alice);
    //     uint256 amount = 100 ether;

    //     uint256 aliceUnderlyingAmount = amount;

    //     underlying.approve(address(vaultHarvester), aliceUnderlyingAmount);
    //     assertEq(
    //         underlying.allowance(alice, address(vaultHarvester)),
    //         aliceUnderlyingAmount
    //     );

    //     uint256 aliceShareAmount = vaultHarvester.deposit(aliceUnderlyingAmount, alice);
    //     vm.stopPrank();

    //     assertEq(vaultHarvester.totalSupply(), aliceShareAmount);
    //     assertEq(vaultHarvester.totalAssets(), 100 ether);
    //     console.log("totalAssets before harvest", vaultHarvester.totalAssets());

    //     assertEq(
    //         ERC20(rewardToken).balanceOf(address(vaultHarvester)),
    //         1000 ether
    //     );
    //     vaultHarvester.claim();
    //     assertEq(ERC20(rewardToken).balanceOf(address(vaultHarvester)), 0);
    //     console.log("totalAssets after harvest", vaultHarvester.totalAssets());
    // }
}
