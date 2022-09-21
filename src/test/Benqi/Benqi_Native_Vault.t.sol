// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "ds-test/test.sol";
import {Utilities} from "../utils/Utilities.sol";
// import {console} from "./utils/Console.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import {BenqiNativeVault, CEther} from "../../Benqi/Benqi_Native_Vault.sol";

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

contract ContractTest is BaseTest {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Meta;
    // using SafeERC20 for Wrapped;
    BenqiNativeVault public benqiVault;
    Wrapped public WAVAX = Wrapped(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    /// @notice TraderJoe router
    UniRouter private joeRouter =
        UniRouter(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
    CEther public cNative = CEther(0x5C0401e81Bc07Ca70fAD469b451682c0d747Ef1c);
    function setUp() public override {
        super.setUp();
        /* ------------------------------- deployments ------------------------------ */
        benqiVault = new BenqiNativeVault(address(cNative),"Benqi ETH Market Vault", "sBETH",address(WAVAX));
    }

    function getWAVAX(uint256 amt) internal {
        deal(address(this), amt);
        WAVAX.deposit{value: amt}();
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

    function testDepositSuccess() public {
        uint256 amt = 2000e18;
        // get 2000 wAVAX to user
        getWAVAX(amt);
        IERC20(WAVAX).approve(address(benqiVault), amt);
        benqiVault.deposit(amt, address(this));
        emit log_named_uint("WAVAX Bal", IERC20(WAVAX).balanceOf(address(this)));
        emit log_named_uint("cNative Bal", CEther(cNative).balanceOf(address(benqiVault)));
    }

    receive() external payable {}

    function testWithdrawSuccess() public {
        uint256 amt = 2000e18;
        // get 2000 wAVAX to user
        getWAVAX(amt);
        
        IERC20(WAVAX).safeApprove(address(benqiVault), amt);
        benqiVault.deposit(amt, address(this));
        emit log_named_uint("WAVAX Bal", IERC20(WAVAX).balanceOf(address(this)));
        emit log_named_uint("cNative Bal", CEther(cNative).balanceOf(address(benqiVault)));
        emit log_named_uint("preview withdrawable before withdraw", benqiVault.maxWithdraw(address(this)));
        benqiVault.withdraw(benqiVault.maxWithdraw(address(this)), address(this), address(this));
        emit log_named_uint("WAVAX Bal after withdraw", IERC20(WAVAX).balanceOf(address(this)));
        emit log_named_uint("avax Bal after withdraw", address(this).balance);
        emit log_named_uint("cNative Bal after withdraw", CEther(cNative).balanceOf(address(benqiVault)));
    }

    function testRedeemSuccess() public {
        uint256 amt = 2000e18;
        // get 2000 wAVAX to user
        getWAVAX(amt);
        IERC20(WAVAX).safeApprove(address(benqiVault), amt);
        benqiVault.deposit(amt, address(this));
        emit log_named_uint("WAVAX Bal", IERC20(WAVAX).balanceOf(address(this)));
        emit log_named_uint("cNative Bal", CEther(cNative).balanceOf(address(benqiVault)));
        benqiVault.redeem(benqiVault.balanceOf(address(this)), address(this), address(this));
        emit log_named_uint("WAVAX Bal after withdraw", IERC20(WAVAX).balanceOf(address(this)));
        emit log_named_uint("cNative Bal after withdraw", CEther(cNative).balanceOf(address(benqiVault)));
    }

    function testSomeViewMethods() public {
        uint256 amt = 2000e18;
        // get 2000 wAVAX to user
        getWAVAX(amt);
        IERC20(WAVAX).safeApprove(address(benqiVault), amt);
        benqiVault.deposit(amt, address(this));
        emit log_named_uint("WAVAX Bal", IERC20(WAVAX).balanceOf(address(this)));
        emit log_named_uint("cNative Bal", CEther(cNative).balanceOf(address(benqiVault)));
        //emit log_named_uint("max Deposits that can be made ", benqiVault.maxDeposit(address(this)));
        //emit log_named_uint("preview withdrawable before withdraw", benqiVault.maxWithdraw(address(this)));
        benqiVault.redeem(benqiVault.balanceOf(address(this)), address(this), address(this));
        emit log_named_uint("WAVAX Bal after withdraw", IERC20(WAVAX).balanceOf(address(this)));
        emit log_named_uint("cNative Bal after withdraw", CEther(cNative).balanceOf(address(benqiVault)));
        
    }
}
