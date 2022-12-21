// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

interface IMultiFeeDistribution {
    
    function getReward() external;

    function exit() external;

}