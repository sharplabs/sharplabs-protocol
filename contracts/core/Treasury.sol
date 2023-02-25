// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/interfaces/IGLPPool.sol";
import "../utils/access/Operator.sol";
import "../utils/token/IERC20.sol";
import "../utils/token/SafeERC20.sol";

contract Treasury is Operator {

    using SafeERC20 for IERC20;

    address governance;
    address glp_pool;
    address glp_pool_hedged;


    modifier onlyGovernance() {
        require(governance == msg.sender, "Boardroom: caller is not the governance");
        _;
    }

    constructor(address _governance, address _glp_pool, address _glp_pool_hedged) {
        governance = _governance;
        glp_pool = _glp_pool;
        glp_pool_hedged = _glp_pool_hedged;
    }

    function buyGLP(
        address _GLPPool, 
        address _token, 
        uint256 _amount, 
        uint256 _minUsdg, 
        uint256 _minGlp
    ) public onlyGovernance{
        IGLPPool(_GLPPool).stakeByGov(_token, _amount, _minUsdg, _minGlp);
    }

    function sellGLP(
        address _GLPPool, 
        address _tokenOut, 
        uint256 _glpAmount, 
        uint256 _minOut, 
        address _receiver
    ) public onlyGovernance{
        IGLPPool(_GLPPool).withdrawByGov(_tokenOut, _glpAmount, _minOut, _receiver);
    }

    function sendPoolFunds(address _glp_pool, address _token, uint _amount) external onlyGovernance{
        IERC20(_token).safeTransfer(_glp_pool, _amount);
    }

    function withdrawPoolFunds(address _glp_pool, address _token, uint _amount) external onlyGovernance{
        IERC20(_token).safeTransferFrom(_glp_pool, address(this), _amount);
    }

    function allocateReward(address _glp_pool, uint256 _amount) public onlyGovernance{
        IGLPPool(_glp_pool).allocateReward(_amount);
    }

    function deposit(address _token, uint256 amount) external onlyGovernance {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(address _token, uint256 amount) external onlyGovernance {
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    function handleStakeRequest(address _glp_pool, address[] memory _address) public onlyGovernance{
        IGLPPool(_glp_pool).handleStakeRequest(_address);
    }

    function handleWithdrawRequest(address _glp_pool, address[] memory _address) public onlyGovernance{
        IGLPPool(_glp_pool).handleWithdrawRequest(_address);
    }

    function setCapacity(uint256 amount) external onlyOperator{
        IGLPPool(glp_pool).setCapacity(amount);
    }

}