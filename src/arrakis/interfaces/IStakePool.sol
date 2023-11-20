// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.23;

interface IStakePool {
    function staking_token() external view returns (address);
}
