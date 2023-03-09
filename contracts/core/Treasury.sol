// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/interfaces/IGLPPool.sol";
import "../utils/access/Operator.sol";
import "../utils/token/IERC20.sol";
import "../utils/token/SafeERC20.sol";

contract Treasury is Operator {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public governance;
    address public riskOffPool;
    address public riskOnPool;

    uint256 public hedgeRatio = 10000;
    uint256 public epoch;
    uint256 public startTime;
    uint256 public period = 8 hours;

    // flags
    bool public initialized = false;

    modifier onlyGovernance() {
        require(governance == msg.sender, "Boardroom: caller is not the governance");
        _;
    }

    modifier notInitialized() {
        require(!initialized, "Boardroom: already initialized");
        _;
    }

    // epoch
    function nextEpochPoint() public view returns (uint256) {
        return startTime.add(epoch.mul(period));
    }

    function isInitialized() public view returns (bool) {
        return initialized;
    }

    function initialize(
        address _governance, 
        address _riskOffPool, 
        address _riskOnPool
    ) public notInitialized {
        governance = _governance;
        riskOffPool = _riskOffPool;
        riskOnPool = _riskOnPool;
        initialized = true;
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

    function sendPoolFunds(address _pool, address _token, uint _amount) external onlyGovernance{
        IERC20(_token).safeTransfer(_pool, _amount);
    }

    function withdrawPoolFunds(address _pool, address _token, uint _amount, address _to) external onlyGovernance{
        require()
        IGLPPool(_pool).treasuryWithdrawFunds(_token, _amount, _to);
    }

    function withdrawPoolFundsETH(address _pool, uint _amount, address _to) external onlyGovernance{
        IGLPPool(_pool).treasuryWithdrawFundsETH(_amount, _to);
    }

    function allocateReward(address _riskOffPool, uint256 _amount) public onlyGovernance{
        IGLPPool(_riskOffPool).allocateReward(_amount);
    }

    function deposit(address _token, uint256 amount) external onlyGovernance {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(address _token, uint256 amount) external onlyGovernance {
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    function handleStakeRequest(address _riskOffPool, address[] memory _address) public onlyGovernance{
        IGLPPool(_riskOffPool).handleStakeRequest(_address);
    }

    function handleWithdrawRequest(address _riskOffPool, address[] memory _address) public onlyGovernance{
        IGLPPool(_riskOffPool).handleWithdrawRequest(_address);
    }

    function setHedgeRatio(uint ratio) external onlyGovernance {
        hedgeRatio = ratio;
    }

    function updateCapacity() external onlyOperator {
        uint amount = IGLPPool(riskOnPool).total_supply_staked() * hedgeRatio / 10000;
        IGLPPool(riskOffPool).setCapacity(amount);
    }

}