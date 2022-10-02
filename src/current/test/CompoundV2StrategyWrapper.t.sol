// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {CompoundV2StrategyWrapper} from "../compound-v2/CompoundV2StrategyWrapper.sol";
import {ICERC20} from "../utils/compound/ICERC20.sol";
import {IComptroller} from "../utils/compound/IComptroller.sol";

contract CompoundV2StrategyWrapperTest is Test {
    uint256 public ethFork;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");

    CompoundV2StrategyWrapper public compoundWrapper;

    ERC20 public asset = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public reward = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ICERC20 public cToken = ICERC20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    IComptroller public comptroller =
        IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);
        compoundWrapper = new CompoundV2StrategyWrapper(
            asset,
            reward,
            cToken,
            comptroller,
            msg.sender
        );
        address alice = address(0x1cA60862a771f1F47d94F87bebE4226141b19C9c);
        vm.prank(alice);
    }

    function testDepositWithdraw() public {}

    function testMintRedeem() public {}
}
