// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IERC20Rebase {

    function getGonsPerFragment() external view returns (uint256);

    function rebase(uint256 supplyDelta, bool negative) external returns (uint256);

    function rebaseSupply() external view returns (uint256);
}