// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

interface IStakePool {
    function staking_token() external view returns (address);
}
