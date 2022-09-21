// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "ds-test/test.sol";
import {Utilities} from "../utils/Utilities.sol";
// import {console} from "./utils/Console.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import {AlpacaNativeVault, IBToken} from "../../Alpaca/Alpaca_Native.sol";

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

contract Alpaca_Native_Test is BaseTest {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Meta;
    // using SafeERC20 for Wrapped;Gsssssssq
    AlpacaNativeVault public AlpacaVault;
    Wrapped public WBNB = Wrapped(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address public alpaca = 0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F;
    /// @notice Pancake router
    UniRouter private cakeRouter =
        UniRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    IBToken public iWBNB = IBToken(0xd7D069493685A581d27824Fc46EdA46B7EfC0063);
    
    function setUp() public override {
        super.setUp();
        /* ------------------------------- deployments ------------------------------ */
        AlpacaVault = new AlpacaNativeVault(address(iWBNB),"Alpaca BNB Market Vault", "sBWBTC", 0xA625AB01B08ce023B2a342Dbb12a16f2C8489A8F, 1);

    }

    function getWBNB(uint256 amt) internal {
        deal(address(this), amt);
        WBNB.deposit{value: amt}();
    }


    function testDepositSuccess() public {
        uint256 amt = 20e18;
        // get 2000 wBNB to user
        getWBNB(amt);

        IERC20(address(WBNB)).safeApprove(address(AlpacaVault), 2*amt);
        uint256 amount = AlpacaVault.mint(AlpacaVault.previewDeposit(amt), address(this));
        console.log("testing this out", amount);
        
        emit log_named_uint("WBNB Bal", IERC20(WBNB).balanceOf(address(this)));
        emit log_named_uint("iWBNB Bal", IBToken(iWBNB).balanceOf(address(AlpacaVault)));
    }

    function testWithdrawSuccess() public {
        uint256 amt = 2000e18;
        // get 2000 wBNB to user
        getWBNB(amt);
        IERC20(WBNB).safeApprove(address(AlpacaVault), amt);
        AlpacaVault.deposit(amt, address(this));
        emit log_named_uint("WBNB Bal", IERC20(WBNB).balanceOf(address(this)));
        emit log_named_uint("iWBNB Bal", IBToken(iWBNB).balanceOf(address(AlpacaVault)));
        emit log_named_uint("vault shares Bal", AlpacaVault.balanceOf(address(this)));
        emit log_named_uint("preview withdrawable before withdraw", AlpacaVault.maxWithdraw(address(this)));
        vm.warp(block.timestamp + 12);
        AlpacaVault.withdraw(AlpacaVault.maxWithdraw(address(this)), address(this), address(this));
        //AlpacaVault.claimRewards();
        emit log_named_uint("Alpaca reward after claiming rewards", IERC20(alpaca).balanceOf(address(this)));
        emit log_named_uint("WBNB Bal after withdraw", IERC20(WBNB).balanceOf(address(this)));
        emit log_named_uint("WBNB Bal after withdraw in Alpaca", IERC20(WBNB).balanceOf(address(AlpacaVault)));
        emit log_named_uint("iWBNB Bal after withdraw", IBToken(iWBNB).balanceOf(address(AlpacaVault)));
        emit log_named_uint("vault shares Bal", AlpacaVault.balanceOf(address(this)));
    }

    function testRedeemSuccess() public {
        uint256 amt = 2000e18;
        // get 2000 wBNB to user
        getWBNB(amt);
        IERC20(WBNB).safeApprove(address(AlpacaVault), amt);
        AlpacaVault.deposit(amt, address(this));
        emit log_named_uint("WBNB Bal", IERC20(WBNB).balanceOf(address(this)));
        emit log_named_uint("iWBNB Bal", IBToken(iWBNB).balanceOf(address(AlpacaVault)));
        vm.warp(block.timestamp + 12);
        AlpacaVault.redeem(AlpacaVault.balanceOf(address(this)), address(this), address(this));
        emit log_named_uint("WBNB Bal after withdraw", IERC20(WBNB).balanceOf(address(this)));
        emit log_named_uint("iWBNB Bal after withdraw", IBToken(iWBNB).balanceOf(address(AlpacaVault)));
    }
    receive() external payable {}
}
