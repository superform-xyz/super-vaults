/// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {AlpacaERC4626Reinvest} from "../AlpacaERC4626Reinvest.sol";

import {IBToken} from "../interfaces/IBToken.sol";
import {IFairLaunch} from "../interfaces/IFairLaunch.sol";

/// NOTE: To fix. Translate all tests, just make it a correct implementation, dont edit.
/// Deployment addresses: https://github.com/alpaca-finance/bsc-alpaca-contract/blob/main/.mainnet.json
contract AlpacaERC4626ReinvestTest is Test {
    uint256 public bscFork;
    address public manager;
    address public alice;

    string BSC_RPC_URL = vm.envString("BSC_RPC_URL");

    AlpacaERC4626Reinvest public vault;

    IBToken public token = IBToken(0x800933D685E7Dc753758cEb77C8bd34aBF1E26d7); /// @dev ibUSDC
    IFairLaunch public fairLaunch = IFairLaunch(0xA625AB01B08ce023B2a342Dbb12a16f2C8489A8F); /// @dev Same addr accross impls

    uint256 poolId; /// @dev Check mainnet.json for poolId
    ERC20 public asset; /// @dev USDC from ib(Token)
    ERC20 public alpacaToken = ERC20(0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F); /// @dev AlpacaToken (reward token)

    function setUp() public {
        bscFork = vm.createFork(BSC_RPC_URL);
        vm.selectFork(bscFork);

        setVault(token, 24);

        manager = msg.sender;
        alice = address(0x1);

        deal(address(asset), alice, 1000 ether);
    }

    function setVault(IBToken asset_, uint256 poolId_) public {
        vm.startPrank(manager);

        token = asset_;
        asset = ERC20(token.token());
        poolId = poolId_;

        vault = new AlpacaERC4626Reinvest(token, fairLaunch, poolId_);

        vm.stopPrank();
    }

    function testDepositWithdraw() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);
        
        uint256 aliceUnderlyingAmount = amount;
        
        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);

        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        vault.withdraw(aliceAssetsToWithdraw, alice, alice);      
    }

}

// pragma solidity ^0.8.14;

// import "forge-std/Test.sol";
// import {ERC20} from "solmate/tokens/ERC20.sol";
// import {AlpacaERC4626Reinvest} from "../AlpacaERC4626Reinvest.sol";

// import {IBToken} from "../interfaces/IBToken.sol";
// import {IFairLaunch} from "../interfaces/IFairLaunch.sol";

// import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
// import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

// interface IERC20Meta is IERC20 {
//     function name() external view returns (string memory);

//     function symbol() external view returns (string memory);
// }

// interface Wrapped is IERC20Meta {
//     function deposit() external payable;
// }


// contract AlpacaERC4626ReinvestTest is Test {

//     AlpacaERC4626Reinvest public AlpacaVault;
//     Wrapped public WBNB = Wrapped(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
//     address public alpaca = 0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F;
//     IBToken public iWBNB = IBToken(0xd7D069493685A581d27824Fc46EdA46B7EfC0063);
    
//     function setUp() public {

//         /* ------------------------------- deployments ------------------------------ */
//         AlpacaVault = new AlpacaERC4626Reinvest(address(iWBNB), 0xA625AB01B08ce023B2a342Dbb12a16f2C8489A8F, 1);

//     }

//     function getWBNB(uint256 amt) internal {
//         deal(address(this), amt);
//         WBNB.deposit{value: amt}();
//     }


//     function testDepositSuccess() public {
//         uint256 amt = 20e18;
//         // get 2000 wBNB to user
//         getWBNB(amt);

//         IERC20(address(WBNB)).safeApprove(address(AlpacaVault), 2*amt);
//         uint256 amount = AlpacaVault.mint(AlpacaVault.previewDeposit(amt), address(this));
//         console.log("testing this out", amount);
        
//         emit log_named_uint("WBNB Bal", IERC20(WBNB).balanceOf(address(this)));
//         emit log_named_uint("iWBNB Bal", IBToken(iWBNB).balanceOf(address(AlpacaVault)));
//     }

//     function testWithdrawSuccess() public {
//         uint256 amt = 2000e18;
//         // get 2000 wBNB to user
//         getWBNB(amt);
//         IERC20(WBNB).safeApprove(address(AlpacaVault), amt);
//         AlpacaVault.deposit(amt, address(this));
//         emit log_named_uint("WBNB Bal", IERC20(WBNB).balanceOf(address(this)));
//         emit log_named_uint("iWBNB Bal", IBToken(iWBNB).balanceOf(address(AlpacaVault)));
//         emit log_named_uint("vault shares Bal", AlpacaVault.balanceOf(address(this)));
//         emit log_named_uint("preview withdrawable before withdraw", AlpacaVault.maxWithdraw(address(this)));
//         vm.warp(block.timestamp + 12);
//         AlpacaVault.withdraw(AlpacaVault.maxWithdraw(address(this)), address(this), address(this));
//         //AlpacaVault.claimRewards();
//         emit log_named_uint("Alpaca reward after claiming rewards", IERC20(alpaca).balanceOf(address(this)));
//         emit log_named_uint("WBNB Bal after withdraw", IERC20(WBNB).balanceOf(address(this)));
//         emit log_named_uint("WBNB Bal after withdraw in Alpaca", IERC20(WBNB).balanceOf(address(AlpacaVault)));
//         emit log_named_uint("iWBNB Bal after withdraw", IBToken(iWBNB).balanceOf(address(AlpacaVault)));
//         emit log_named_uint("vault shares Bal", AlpacaVault.balanceOf(address(this)));
//     }

//     function testRedeemSuccess() public {
//         uint256 amt = 2000e18;
//         // get 2000 wBNB to user
//         getWBNB(amt);
//         IERC20(WBNB).safeApprove(address(AlpacaVault), amt);
//         AlpacaVault.deposit(amt, address(this));
//         emit log_named_uint("WBNB Bal", IERC20(WBNB).balanceOf(address(this)));
//         emit log_named_uint("iWBNB Bal", IBToken(iWBNB).balanceOf(address(AlpacaVault)));
//         vm.warp(block.timestamp + 12);
//         AlpacaVault.redeem(AlpacaVault.balanceOf(address(this)), address(this), address(this));
//         emit log_named_uint("WBNB Bal after withdraw", IERC20(WBNB).balanceOf(address(this)));
//         emit log_named_uint("iWBNB Bal after withdraw", IBToken(iWBNB).balanceOf(address(AlpacaVault)));
//     }
//     receive() external payable {}

// }
