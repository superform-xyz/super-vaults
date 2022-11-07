// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/// If User gives TokenA and wants to enter Pool A/B, we need to swap 100% of TokenA to 50/50 A/B
/// With swap built-in deposit() of ERC4626, we would always need to deploy a vault with underlying from which to swap
/// With SuperForm, for UniV2 DAI/USDC, one Vault with DAI as underlying (swaping to USDC) and one Vault with USDC as underlying (swap to DAI)
/// This means deployment of at least two separate Vaults to enter into 1 double token pool

/// With no-swap our "custom" Wrapper expects DAI & USDC to be available at the Destination when processing payload and then "yanks" them out for deposit
/// Amount of LP expected from DAI&USDC provided is used as asset argument and validation 

contract ZapIntoDoubleSide {
    address public immutable manager;
    ERC4626 public vault;

    constructor(
        ERC4626 vault_
    ) {
        vault = vault_;
        manager = msg.sender;
    }

    function optimalDeposit(ERC4626 vault_) public {
        /// Read tokens neeeded for deposit at given Vault
        /// Calculate optimal amounts out of reserves
        /// Pass call to ERC4626 double-sided
    }


}
