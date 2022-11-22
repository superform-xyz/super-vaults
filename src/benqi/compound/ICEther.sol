// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";

abstract contract ICEther is ERC20 {
    function comptroller() external view virtual returns (address);

    function getCash() external view virtual returns (uint256);

    function getAccountSnapshot(address)
        external
        view
        virtual
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );
    function redeemUnderlying(uint256) external virtual returns (uint256);
    function mint() external payable virtual;
    
    function exchangeRateStored() external virtual view returns (uint);
}