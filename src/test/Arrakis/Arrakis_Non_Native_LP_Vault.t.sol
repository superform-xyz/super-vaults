// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import {Utilities} from "../utils/Utilities.sol";
// import {console} from "./utils/Console.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import {ArrakisNonNativeVault, IArrakisRouter} from "../../Arrakis/Arrakis_Non_Native_LP_Vault.sol";
import {BenqiClaimer} from "../../Benqi/Benqi_reward_Claimer.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

interface IERC20Meta is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);
}

interface Wrapped is IERC20Meta {
    function deposit() external payable;
}

contract BaseTest is DSTest, Test {

    Utilities internal utils;
    address payable[] internal users;

    function setUp() public virtual {
        utils = new Utilities();
        users = utils.createUsers(5);
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
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Meta;
    IERC20 public arrakisVault;
    // using SafeERC20 for Wrapped;
    ArrakisNonNativeVault public arrakisNonNativeVault;
    ArrakisNonNativeVault public arrakisToken1AsAssetVault;
    BenqiClaimer public benqiClaimer;
    Wrapped public WMATIC = Wrapped(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address public USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    /// @notice TraderJoe router
    UniRouter private joeRouter =
        UniRouter(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
    function setUp() public override {
        super.setUp();
        /* ------------------------------- deployments ------------------------------ */
        arrakisVault = IERC20(0x4520c823E3a84ddFd3F99CDd01b2f8Bf5372A82a);
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
        IERC20(path[0]).safeApprove(address(joeRouter), amtIn);
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
        IERC20(address(WMATIC)).safeApprove(address(arrakisNonNativeVault), amt);
        arrakisNonNativeVault.computeFeesAccrued();
        emit log_named_uint("deposited amount:", 2000e18);
        arrakisNonNativeVault.deposit(amt, address(this));
        console.log("Starting swap simulation on uniswap....");
        uint256 countLoop = 2;
        IERC20(address(WMATIC)).transfer(address(arrakisNonNativeVault),298000e18);
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
        IERC20(address(USDC)).safeApprove(address(arrakisToken1AsAssetVault), amountUSDC);
        arrakisToken1AsAssetVault.computeFeesAccrued();
        emit log_named_uint("deposited amount:",2000*(10**6) );
        arrakisToken1AsAssetVault.deposit(2000*(10**6), address(this));
        console.log("Starting swap simulation on uniswap....");
        uint256 countLoop = 2;
        IERC20(address(USDC)).transfer(address(arrakisToken1AsAssetVault),IERC20(address(USDC)).balanceOf(address(this)));
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

    // function testWithdrawSuccess() public {
    //     uint256 amt = 2000e18;
    //     // get 2000 wAVAX to user
    //     getWAVAX(amt);
    //     // swap for WETH
    //     address[] memory path = new address[](2);
    //     path[0] = address(WAVAX);
    //     path[1] = WETH;
    //     assertTrue(IERC20(WETH).balanceOf(address(this)) == 0);
    //     uint256 amountETH = swap(amt, path);
    //     emit log_named_uint("WETH Bal", IERC20(WETH).balanceOf(address(this)));
    //     IERC20(path[1]).safeApprove(address(benqiVault), amountETH);
    //     benqiVault.deposit(amountETH, address(this));
    //     emit log_named_uint("WETH Bal", IERC20(WETH).balanceOf(address(this)));
    //     emit log_named_uint("cETH Bal", CToken(cETH).balanceOf(address(benqiVault)));
    //     emit log_named_uint("preview withdrawable before withdraw", benqiVault.maxWithdraw(address(this)));
    //     benqiVault.withdraw(benqiVault.maxWithdraw(address(this)), address(this), address(this));
    //     emit log_named_uint("WETH Bal after withdraw", IERC20(WETH).balanceOf(address(this)));
    //     emit log_named_uint("cETH Bal after withdraw", CToken(cETH).balanceOf(address(benqiVault)));
    // }

    // function testRedeemSuccess() public {
    //     uint256 amt = 2000e18;
    //     // get 2000 wAVAX to user
    //     getWAVAX(amt);
    //     // swap for WETH
    //     address[] memory path = new address[](2);
    //     path[0] = address(WAVAX);
    //     path[1] = WETH;
    //     assertTrue(IERC20(WETH).balanceOf(address(this)) == 0);
    //     uint256 amountETH = swap(amt, path);
    //     emit log_named_uint("WETH Bal", IERC20(WETH).balanceOf(address(this)));
    //     IERC20(path[1]).safeApprove(address(benqiVault), amountETH);
    //     benqiVault.deposit(amountETH, address(this));
    //     emit log_named_uint("WETH Bal", IERC20(WETH).balanceOf(address(this)));
    //     emit log_named_uint("cETH Bal", CToken(cETH).balanceOf(address(benqiVault)));
    //     benqiVault.redeem(benqiVault.balanceOf(address(this)), address(this), address(this));
    //     emit log_named_uint("WETH Bal after withdraw", IERC20(WETH).balanceOf(address(this)));
    //     emit log_named_uint("cETH Bal after withdraw", CToken(cETH).balanceOf(address(benqiVault)));
    // }

    // function testSomeViewMethods() public {
    //     uint256 amt = 2000e18;
    //     // get 2000 wAVAX to user
    //     getWAVAX(amt);
    //     // swap for WETH
    //     address[] memory path = new address[](2);
    //     path[0] = address(WAVAX);
    //     path[1] = WETH;
    //     assertTrue(IERC20(WETH).balanceOf(address(this)) == 0);
    //     uint256 amountETH = swap(amt, path);
    //     emit log_named_uint("WETH Bal", IERC20(WETH).balanceOf(address(this)));
    //     IERC20(path[1]).safeApprove(address(benqiVault), amountETH);
    //     benqiVault.deposit(amountETH, address(this));
    //     emit log_named_uint("WETH Bal", IERC20(WETH).balanceOf(address(this)));
    //     emit log_named_uint("cETH Bal", CToken(cETH).balanceOf(address(benqiVault)));
    //     //emit log_named_uint("max Deposits that can be made ", benqiVault.maxDeposit(address(this)));
    //     //emit log_named_uint("preview withdrawable before withdraw", benqiVault.maxWithdraw(address(this)));
    //     benqiVault.redeem(benqiVault.balanceOf(address(this)), address(this), address(this));
    //     emit log_named_uint("WETH Bal after withdraw", IERC20(WETH).balanceOf(address(this)));
    //     emit log_named_uint("cETH Bal after withdraw", CToken(cETH).balanceOf(address(benqiVault)));
    // }

    receive() external payable {}
}
