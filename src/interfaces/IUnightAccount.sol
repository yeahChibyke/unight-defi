// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMidnight} from "./IMidnight.sol";

interface IUnightAccount {
    function owner() external view returns (address);

    function marketId() external view returns (bytes32);

    function registerBidContext(
        bytes32 offerHash,
        IMidnight.Market calldata market,
        address taker,
        uint128 maxAssets,
        uint256 deadline,
        bytes calldata callbackData
    ) external;
}
