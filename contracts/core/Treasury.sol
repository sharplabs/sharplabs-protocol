// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/interfaces/IGLPPool.sol";
import "../utils/access/Operator.sol";

contract Treasury is Operator {

    address governance;

    constructor(address _governance) {
        governance = _governance;
    }

    function(uint256 _addr) public {

    }

    function buyGLP(
        address _GLPPool, 
        address _token, 
        uint256 _amount, 
        uint256 _minUsdg, 
        uint256 _minGlp
    ) public {
        IGLPPool(_GLPPool).stakeByGov(_token, _amount, _minUsdg, _minGlp);
    }

    function sellGLP(
        address _GLPPool, 
        address _tokenOut, 
        uint256 _glpAmount, 
        uint256 _minOut, 
        address _receiver
    ) public {
        IGLPPool(_GLPPool).withdrawByGov(_tokenOut, _glpAmount, _minOut, _receiver);
    }

    function handleStakeRequest(address _GLPPool) public {
        IGLPPool(_GLPPool).handleStakeRequest();
    }

    function handleWithdrawRequest(address _GLPPool) public {
        IGLPPool(_GLPPool).handleWithdrawRequest();
    }

    function handleAtEveryEpoch(
        address _GLPPool, 
        address _token, 
        uint256 _amount, 
        uint256 _minUsdg, 
        uint256 _minGlp,
        address _tokenOut, 
        uint256 _glpAmount, 
        uint256 _minOut, 
        address _receiver,
        uint256 _funds
    ) external {
        stakeGLP(_GLPPool, _token, _amount, _minUsdg, _minGlp);
        handleStakeRequest(_GLPPool);
        withdrawGLP(_GLPPool, _tokenOut, _glpAmount, _minOut, _receiver);
        handleWithdrawRequest(_GLPPool);
        allocateFunds(_GLPPool, _funds);
        
    }

    function allocateFunds(address _GLPPool, uint256 _amount) public {
        IGLPPool(_GLPPool).allocateFunds(_amount);
    }

    function withdrawGLPPoolFunds(address _GLPPoool, address _token, uint amount) external {
        
    }

    function sendFundsAndReward(address _token, address _amount) external {

    }
}