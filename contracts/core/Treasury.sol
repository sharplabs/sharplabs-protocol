// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/interface/IGLPPool.sol";
import "../utils/access/Operator.sol";

contract Treasury is Operator {
    function stakeGLP(address _GLPPool) external {
        
        IGLPPool(_GLPPool).stakeByGov()
    }
    
    function withdrawGLP() external {

    }

    function withdrawGLPPoolFunds(address _GLPPoool, address _token, uint amount) external {

    }

    function sendFundsAndReward(address _token, address _amount) external {

    }
}