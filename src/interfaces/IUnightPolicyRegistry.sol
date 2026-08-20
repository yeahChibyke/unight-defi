// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IUnightPolicyRegistry {
    function isPoolApproved(bytes32 poolId) external view returns (bool);

    function isMarketApproved(bytes32 marketId) external view returns (bool);

    function isRatifierApproved(address ratifier) external view returns (bool);

    function isDormancyOracleApproved(address oracle) external view returns (bool);
}
