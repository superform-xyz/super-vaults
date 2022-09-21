// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "ds-test/test.sol";
import {Utilities} from "../utils/Utilities.sol";
// import {console} from "./utils/Console.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import {AlpacaBTCVault, IBToken} from "../../Alpaca/Alpaca_BTC_Vault.sol";

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

contract Alpaca_BTC_Test is BaseTest {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Meta;
    // using SafeERC20 for Wrapped;Gsssssssq
    AlpacaBTCVault public AlpacaVault;
    Wrapped public WBNB = Wrapped(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    /// @notice Pancake router
    UniRouter private cakeRouter =
        UniRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    IBToken public iWBTC = IBToken(0x08FC9Ba2cAc74742177e0afC3dC8Aed6961c24e7);
    address private WBTC = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c;
    IERC20 public alpacaToken = IERC20(0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F);
    function setUp() public override {
        super.setUp();
        /* ------------------------------- deployments ------------------------------ */
        AlpacaVault = new AlpacaBTCVault(address(iWBTC),"Alpaca BTC Market Vault", "sBWBTC", 0xA625AB01B08ce023B2a342Dbb12a16f2C8489A8F, 18, 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56,
        0x7752e1FA9F3a2e860856458517008558DEb989e3,0xF45cd219aEF8618A92BAa7aD848364a158a24F33);

    }

    function getWBNB(uint256 amt) internal {
        deal(address(this), amt);
        WBNB.deposit{value: amt}();
    }

    function swap(uint256 amtIn, address[] memory path)
        internal
        returns (uint256)
    {
        IERC20(path[0]).safeApprove(address(cakeRouter), amtIn);
        uint256[] memory amts = cakeRouter.swapExactTokensForTokens(
            amtIn,
            0,
            path,
            address(this),
            block.timestamp + 1
        );
        return amts[amts.length - 1];
    }

    function testDepositSuccess() public {
        uint256 amt = 20e18;
        // get 2000 wBNB to user
        getWBNB(amt);
        // swap for WBTC
        address[] memory path = new address[](2);
        path[0] = address(WBNB);
        path[1] = WBTC;
        assertTrue(IERC20(WBTC).balanceOf(address(this)) == 0);
        uint256 amountBTC = swap(amt, path);
        console.log("calling contract",address(this));
        IERC20(path[1]).safeApprove(address(AlpacaVault), 2*amountBTC);
        uint256 amount = AlpacaVault.mint(AlpacaVault.previewDeposit(amountBTC), address(this));
        console.log("testing this out", amount);
        
        emit log_named_uint("WBTC Bal", IERC20(WBTC).balanceOf(address(this)));
        emit log_named_uint("iWBTC Bal", IBToken(iWBTC).balanceOf(address(AlpacaVault)));
    }

    function testWithdrawSuccess() public {
        uint256 amt = 2000e18;
        // get 2000 wBNB to user
        getWBNB(amt);
        // swap for WBTC
        address[] memory path = new address[](2);
        path[0] = address(WBNB);
        path[1] = WBTC;
        assertTrue(IERC20(WBTC).balanceOf(address(this)) == 0);
        uint256 amountBTC = swap(amt, path);
        //emit log_named_uint("WBTC Bal", IERC20(WBTC).balanceOf(address(this)));
        emit log_named_uint("WBTC Bal", amountBTC);
        // IERC20(path[1]).safeApprove(address(iWBTC), amountBTC);
        // IBToken(iWBTC).deposit(amountBTC);
        // IBToken(iWBTC).withdraw(IBToken(iWBTC).balanceOf(address(this)));
        // emit log_named_uint("WBTC Bal", IERC20(WBTC).balanceOf(address(this)));
        IERC20(path[1]).safeApprove(address(AlpacaVault), amountBTC);
        AlpacaVault.deposit(amountBTC, address(this));
        emit log_named_uint("WBTC Bal", IERC20(WBTC).balanceOf(address(this)));
        emit log_named_uint("iWBTC Bal", IBToken(iWBTC).balanceOf(address(AlpacaVault)));
        emit log_named_uint("vault shares Bal", AlpacaVault.balanceOf(address(this)));
        emit log_named_uint("preview withdrawable before withdraw", AlpacaVault.maxWithdraw(address(this)));
        vm.warp(block.timestamp + 12);
        //AlpacaVault.withdraw(AlpacaVault.maxWithdraw(address(this)), address(this), address(this));
        AlpacaVault.reinvest();
        emit log_named_uint("alpaca Bal after withdraw", alpacaToken.balanceOf(address(AlpacaVault)));
        emit log_named_uint("WBTC Bal after withdraw", IERC20(WBTC).balanceOf(address(this)));
        emit log_named_uint("WBTC Bal after withdraw in Alpaca", IERC20(WBTC).balanceOf(address(AlpacaVault)));
        emit log_named_uint("iWBTC Bal after withdraw", IBToken(iWBTC).balanceOf(address(AlpacaVault)));
        emit log_named_uint("vault shares Bal", AlpacaVault.balanceOf(address(this)));
    }

    function testRedeemSuccess() public {
        uint256 amt = 2000e18;
        // get 2000 wBNB to user
        getWBNB(amt);
        // swap for WBTC
        address[] memory path = new address[](2);
        path[0] = address(WBNB);
        path[1] = WBTC;
        assertTrue(IERC20(WBTC).balanceOf(address(this)) == 0);
        uint256 amountBTC = swap(amt, path);
        emit log_named_uint("WBTC Bal", IERC20(WBTC).balanceOf(address(this)));
        IERC20(path[1]).safeApprove(address(AlpacaVault), amountBTC);
        AlpacaVault.deposit(amountBTC, address(this));
        emit log_named_uint("WBTC Bal", IERC20(WBTC).balanceOf(address(this)));
        emit log_named_uint("iWBTC Bal", IBToken(iWBTC).balanceOf(address(AlpacaVault)));
        vm.warp(block.timestamp + 1);
        AlpacaVault.redeem(AlpacaVault.balanceOf(address(this)), address(this), address(this));
        emit log_named_uint("WBTC Bal after withdraw", IERC20(WBTC).balanceOf(address(this)));
        emit log_named_uint("iWBTC Bal after withdraw", IBToken(iWBTC).balanceOf(address(AlpacaVault)));
    }

    function testSomeViewMBTCods() public {
        uint256 amt = 2000e18;
        // get 2000 wBNB to user
        getWBNB(amt);
        // swap for WBTC
        address[] memory path = new address[](2);
        path[0] = address(WBNB);
        path[1] = WBTC;
        assertTrue(IERC20(WBTC).balanceOf(address(this)) == 0);
        uint256 amountBTC = swap(amt, path);
        emit log_named_uint("WBTC Bal", IERC20(WBTC).balanceOf(address(this)));
        IERC20(path[1]).safeApprove(address(AlpacaVault), amountBTC);
        AlpacaVault.deposit(amountBTC, address(this));
        emit log_named_uint("WBTC Bal", IERC20(WBTC).balanceOf(address(this)));
        emit log_named_uint("iWBTC Bal", IBToken(iWBTC).balanceOf(address(AlpacaVault)));
        //emit log_named_uint("max Deposits that can be made ", AlpacaVault.maxDeposit(address(this)));
        //emit log_named_uint("preview withdrawable before withdraw", AlpacaVault.maxWithdraw(address(this)));
        vm.warp(block.timestamp + 1);
        AlpacaVault.redeem(AlpacaVault.balanceOf(address(this)), address(this), address(this));
        emit log_named_uint("WBTC Bal after withdraw", IERC20(WBTC).balanceOf(address(this)));
        emit log_named_uint("iWBTC Bal after withdraw", IBToken(iWBTC).balanceOf(address(AlpacaVault)));
    }

    receive() external payable {}
}
