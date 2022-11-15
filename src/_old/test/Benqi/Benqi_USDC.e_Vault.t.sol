// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

// import "ds-test/test.sol";
import {Utilities} from "../utils/Utilities.sol";
// import {console} from "./utils/Console.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import {BenqiEthVault, CToken} from "../../Benqi/Benqi_ETH_Vault.sol";
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

contract BenqiUSDCTest is BaseTest {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Meta;
    // using SafeERC20 for Wrapped;
    BenqiEthVault public benqiVault;
    BenqiClaimer public benqiClaimer;
    IERC20 qiToken = IERC20(0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5);
    Wrapped public WAVAX = Wrapped(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    /// @notice TraderJoe router
    UniRouter private joeRouter =
        UniRouter(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
    CToken public cUSDC = CToken(0xB715808a78F6041E46d61Cb123C9B4A27056AE9C);
    address private USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    // function _labelCToken(CToken cToken) internal {
    //     label(address(cToken), IERC20Meta(address(cToken)).symbol());
    //     address vault = cToken.underlying();
    //     label(vault, IERC20Meta(vault).name());
    // }
    function setUp() public override {
        super.setUp();
        /* ------------------------------- deployments ------------------------------ */
        IERC20 qiToken = IERC20(0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5);
        benqiClaimer = new BenqiClaimer(0x486Af39519B4Dc9a7fCcd318217352830E8AD9b4,address(WAVAX),0xE530dC2095Ef5653205CF5ea79F8979a7028065c, 0x0e0100Ab771E9288e0Aa97e11557E6654C3a9665,address(qiToken));
        benqiVault = new BenqiEthVault(address(cUSDC),"Benqi USDC Market Vault", "sBUSDC", address(benqiClaimer));

        /* --------------------------------- labels --------------------------------- */
        // label(address(benqiVault), "vault");
        // label(address(cUSDC), "cUSDC");
        // _labelCToken(cUSDC);
        benqiClaimer.setVault(address(benqiVault));
        benqiClaimer.setRewardToken(0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5);
        benqiClaimer.setRewardToken(address(0));
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
        // swap for WUSDC
        address[] memory path = new address[](2);
        path[0] = address(WAVAX);
        path[1] = USDC;
        assertTrue(IERC20(USDC).balanceOf(address(this)) == 0);
        uint256 amountUSDC = swap(amt, path);
        IERC20(path[1]).safeApprove(address(benqiVault), amountUSDC);
        benqiVault.deposit(amountUSDC, address(this));
        emit log_named_uint("USDC Bal", IERC20(USDC).balanceOf(address(this)));
        emit log_named_uint("cUSDC Bal", CToken(cUSDC).balanceOf(address(benqiVault)));
    }

    function testWithdrawSuccess() public {
        uint256 amt = 2000e18;
        // get 2000 wAVAX to user
        getWAVAX(amt);
        // swap for USDC
        address[] memory path = new address[](2);
        path[0] = address(WAVAX);
        path[1] = USDC;
        assertTrue(IERC20(USDC).balanceOf(address(this)) == 0);
        uint256 amountUSDC = swap(amt, path);
        emit log_named_uint("USDC Bal", IERC20(USDC).balanceOf(address(this)));
        IERC20(path[1]).safeApprove(address(benqiVault), amountUSDC);
        benqiVault.deposit(amountUSDC, address(this));
        emit log_named_uint("USDC Bal", IERC20(USDC).balanceOf(address(this)));
        emit log_named_uint("cUSDC Bal", CToken(cUSDC).balanceOf(address(benqiVault)));
        emit log_named_uint("preview withdrawable before withdraw", benqiVault.maxWithdraw(address(this)));
        // we are warping it
        vm.warp(block.timestamp + 12);
        benqiVault.withdraw(benqiVault.maxWithdraw(address(this)), address(this), address(this));
            emit log_named_uint("Qi rewards accrued after warping 12 blocks", benqiClaimer.rewardsAccrued(0));
            emit log_named_uint("AVAX rewards accrued after warping 12 blocks", benqiClaimer.rewardsAccrued(1));
        benqiVault.claimRewards();
        emit log_named_uint("qi bal after warping 12 blocks", qiToken.balanceOf(address(benqiVault)));
        emit log_named_uint("AVAX bal after warping 12 blocks", address(benqiVault).balance);

        emit log_named_uint("USDC Bal after withdraw", IERC20(USDC).balanceOf(address(this)));
        emit log_named_uint("cUSDC Bal after withdraw", CToken(cUSDC).balanceOf(address(benqiVault)));
    }

    function testReinvestSuccess() public {
        uint256 amt = 2000e18;
        // get 2000 wAVAX to user
        getWAVAX(amt);
        // swap for USDC
        address[] memory path = new address[](2);
        path[0] = address(WAVAX);
        path[1] = USDC;
        assertTrue(IERC20(USDC).balanceOf(address(this)) == 0);
        uint256 amountUSDC = swap(amt, path);
        emit log_named_uint("USDC Bal", IERC20(USDC).balanceOf(address(this)));
        IERC20(path[1]).safeApprove(address(benqiVault), amountUSDC);
        benqiVault.deposit(amountUSDC, address(this));
        emit log_named_uint("USDC Bal", IERC20(USDC).balanceOf(address(this)));
        emit log_named_uint("cUSDC Bal", CToken(cUSDC).balanceOf(address(benqiVault)));
        emit log_named_uint("preview withdrawable before withdraw", benqiVault.maxWithdraw(address(this)));
        // we are warping it
        vm.warp(block.timestamp + 1200);
        //benqiVault.withdraw(benqiVault.maxWithdraw(address(this)), address(this), address(this));
        emit log_named_uint("Qi rewards accrued after warping 12 blocks", benqiClaimer.rewardsAccrued(0));
        emit log_named_uint("AVAX rewards accrued after warping 12 blocks", benqiClaimer.rewardsAccrued(1));
        benqiVault.claimRewards();
        emit log_named_uint("qi bal after warping 12 blocks", qiToken.balanceOf(address(benqiVault)));
        emit log_named_uint("AVAX bal after warping 12 blocks", address(benqiVault).balance);
        emit log_named_uint("USDC Bal after claim", IERC20(USDC).balanceOf(address(benqiClaimer)));
        emit log_named_uint("vault underlying balance before re-invest", benqiVault.totalAssets());
        benqiVault.reinvest();
        emit log_named_uint("vault underlying balance after re-invest", benqiVault.totalAssets());
        // emit log_named_uint("USDC Bal after withdraw", IERC20(USDC).balanceOf(address(this)));
        // emit log_named_uint("cUSDC Bal after withdraw", CToken(cUSDC).balanceOf(address(benqiVault)));
    }

    function testRedeemSuccess() public {
        uint256 amt = 2000e18;
        // get 2000 wAVAX to user
        getWAVAX(amt);
        // swap for USDC
        address[] memory path = new address[](2);
        path[0] = address(WAVAX);
        path[1] = USDC;
        assertTrue(IERC20(USDC).balanceOf(address(this)) == 0);
        uint256 amountETH = swap(amt, path);
        emit log_named_uint("USDC Bal", IERC20(USDC).balanceOf(address(this)));
        
        IERC20(path[1]).safeApprove(address(benqiVault), amountETH);
        benqiVault.deposit(amountETH, address(this));
        emit log_named_uint("USDC Bal", IERC20(USDC).balanceOf(address(this)));
        emit log_named_uint("cUSDC Bal", CToken(cUSDC).balanceOf(address(benqiVault)));
        benqiVault.redeem(benqiVault.balanceOf(address(this)), address(this), address(this));
        emit log_named_uint("USDC Bal after withdraw", IERC20(USDC).balanceOf(address(this)));
        emit log_named_uint("cUSDC Bal after withdraw", CToken(cUSDC).balanceOf(address(benqiVault)));
    }

    function testSomeViewMethods() public {
        uint256 amt = 2000e18;
        // get 2000 wAVAX to user
        getWAVAX(amt);
        // swap for USDC
        address[] memory path = new address[](2);
        path[0] = address(WAVAX);
        path[1] = USDC;
        assertTrue(IERC20(USDC).balanceOf(address(this)) == 0);
        uint256 amountETH = swap(amt, path);
        emit log_named_uint("USDC Bal", IERC20(USDC).balanceOf(address(this)));
        IERC20(path[1]).safeApprove(address(benqiVault), amountETH);
        benqiVault.deposit(amountETH, address(this));
        emit log_named_uint("USDC Bal", IERC20(USDC).balanceOf(address(this)));
        emit log_named_uint("cUSDC Bal", CToken(cUSDC).balanceOf(address(benqiVault)));
        //emit log_named_uint("max Deposits that can be made ", benqiVault.maxDeposit(address(this)));
        //emit log_named_uint("preview withdrawable before withdraw", benqiVault.maxWithdraw(address(this)));
        benqiVault.redeem(benqiVault.balanceOf(address(this)), address(this), address(this));
        emit log_named_uint("USDC Bal after withdraw", IERC20(USDC).balanceOf(address(this)));
        emit log_named_uint("cUSDC Bal after withdraw", CToken(cUSDC).balanceOf(address(benqiVault)));
    }

    receive() external payable {}
}
