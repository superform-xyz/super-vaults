// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;


import {Utilities} from "./utils/Utilities.sol";
// import {console} from "./utils/Console.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import {ArrakisNonNativeVault, IArrakisRouter} from "../Arrakis/Arrakis_Non_Native_LP_Vault.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IWETH} from "../token-staking/interfaces/IWETH.sol";


contract BaseTest is DSTest, Test {

    Utilities internal utils;
    address payable[] internal users;

    function setUp() public virtual {
       // utils = new Utilities();
     //   users = utils.createUsers(5);
    }
}

interface UniRouter {
    function factory() external view returns (address);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract Arrakis_LP_Test is BaseTest {
    uint256 public maticFork;
    string POLYGON_MAINNET_RPC = vm.envString("POLYGON_MAINNET_RPC");
    ERC20 public arrakisVault;
    // using SafeERC20 for Wrapped;
    ArrakisNonNativeVault public arrakisNonNativeVault;
    ArrakisNonNativeVault public arrakisToken1AsAssetVault;
    IWETH public WMATIC = IWETH(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address public USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    /// @notice TraderJoe router
    UniRouter private joeRouter =
        UniRouter(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
    function setUp() public override {
        maticFork = vm.createFork(POLYGON_MAINNET_RPC);
       // super.setUp();
        vm.selectFork(maticFork);
        console.log("It tried to go till here");
        /* ------------------------------- deployments ------------------------------ */
        arrakisVault = ERC20(0x4520c823E3a84ddFd3F99CDd01b2f8Bf5372A82a);
        // with WMATIC as asset
        arrakisNonNativeVault = new ArrakisNonNativeVault(address(arrakisVault),"Arrakis WMATIC/USDC LP Vault", "aLP4626", true, 0xbc91a120cCD8F80b819EAF32F0996daC3Fa76a6C, 0x9941C03D31BC8B3aA26E363f7DD908725e1a21bb, 50);
        // with USDC as an asset in WMATIC/USDC univ3 LP
        arrakisToken1AsAssetVault = new ArrakisNonNativeVault(address(arrakisVault),"Arrakis WMATIC/USDC LP Vault", "aLP4626", false, 0xbc91a120cCD8F80b819EAF32F0996daC3Fa76a6C, 0x9941C03D31BC8B3aA26E363f7DD908725e1a21bb, 50);
    }

    function getWMATIC(uint256 amt) internal {
        deal(address(this), amt);
        WMATIC.deposit{value: amt}();
    }

    function swap(uint256 amtIn, address[] memory path)
        internal
        returns (uint256)
    {
        ERC20(path[0]).approve(address(joeRouter), amtIn);
        uint256[] memory amts = joeRouter.swapExactTokensForTokens(
            amtIn,
            0,
            path,
            address(this),
            block.timestamp + 1
        );
        return amts[amts.length - 1];
    }

    function testDepositWithToken0AsAssetSuccess() public {
        uint256 amt = 300000e18;
        // get 2000 WMATIC to user
        getWMATIC(amt);
        amt = 2000e18;
        ERC20(address(WMATIC)).approve(address(arrakisNonNativeVault), amt);
        arrakisNonNativeVault.computeFeesAccrued();
        emit log_named_uint("deposited amount:", 2000e18);
        arrakisNonNativeVault.deposit(amt, address(this));
        console.log("Starting swap simulation on uniswap....");
        uint256 countLoop = 2;
        ERC20(address(WMATIC)).transfer(address(arrakisNonNativeVault),298000e18);
        while(countLoop >0){
            arrakisNonNativeVault.swap();
            countLoop--;
        }
        arrakisNonNativeVault.emergencyWithdrawAssets();
        console.log("swap simulation on uniswap stopped!");
        //arrakisNonNativeVault.approveTokenIfNeeded(address(WMATIC), address(this));
        //IERC20(address(WMATIC)).safeTransferFrom(address(arrakisNonNativeVault),address(this), IERC20(address(WMATIC)).balanceOf(address(arrakisNonNativeVault)));
        arrakisNonNativeVault.computeFeesAccrued();
        uint256 returnAssets = arrakisNonNativeVault.redeem(arrakisNonNativeVault.balanceOf(address(this)), address(this), address(this));
        //emit log_named_uint("amount gained through out the duration in the form of deposited Asset", returnAssets);
        emit log_named_decimal_uint("amount gained through out the duration in the form of deposited Asset", returnAssets - amt, 18);
    }

    function testDepositWithToken1AsAssetSuccess() public {
        uint256 amt = 300000e18;
        // get 2000 WMATIC to user
        getWMATIC(amt);
        // swap for WBTC
        address[] memory path = new address[](2);
        path[0] = address(WMATIC);
        path[1] = USDC;
        uint256 amountUSDC = swap(amt, path);
        ERC20(address(USDC)).approve(address(arrakisToken1AsAssetVault), amountUSDC);
        arrakisToken1AsAssetVault.computeFeesAccrued();
        emit log_named_uint("deposited amount:",2000*(10**6) );
        arrakisToken1AsAssetVault.deposit(2000*(10**6), address(this));
        console.log("Starting swap simulation on uniswap....");
        uint256 countLoop = 2;
        ERC20(address(USDC)).transfer(address(arrakisToken1AsAssetVault),ERC20(address(USDC)).balanceOf(address(this)));
        while(countLoop >0){
            arrakisToken1AsAssetVault.swap();
            countLoop--;
        }
        arrakisToken1AsAssetVault.emergencyWithdrawAssets();
        console.log("swap simulation on uniswap stopped!");
        //arrakisNonNativeVault.approveTokenIfNeeded(address(WMATIC), address(this));
        //IERC20(address(WMATIC)).safeTransferFrom(address(arrakisNonNativeVault),address(this), IERC20(address(WMATIC)).balanceOf(address(arrakisNonNativeVault)));
        arrakisToken1AsAssetVault.computeFeesAccrued();
        uint256 returnAssets = arrakisToken1AsAssetVault.redeem(arrakisToken1AsAssetVault.balanceOf(address(this)), address(this), address(this));
        //emit log_named_uint("amount gained through out the duration in the form of deposited Asset", returnAssets);
        emit log_named_decimal_uint("amount gained through out the duration in the form of deposited Asset", returnAssets, 6);
    }

    receive() external payable {}
}
