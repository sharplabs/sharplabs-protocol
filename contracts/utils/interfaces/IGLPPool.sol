// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IGLPPool {
    function receiveFundsAndReward(
        address _token,
        uint _amount
    ) external;
}    
    