// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

/// https://github.com/rocket-pool/rocketpool/blob/master/contracts/interface/dao/protocol/settings/RocketDAOProtocolSettingsDepositInterface.sol
interface IRPROTOCOL {
    function getDepositEnabled() external view returns (bool);
    function getAssignDepositsEnabled() external view returns (bool);
    function getMinimumDeposit() external view returns (uint256);
    function getMaximumDepositPoolSize() external view returns (uint256);
    function getMaximumDepositAssignments() external view returns (uint256);
    function getDepositFee() external view returns (uint256);
}