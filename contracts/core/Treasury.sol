// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/interfaces/IGLPPool.sol";
import "../utils/access/Operator.sol";
import "../utils/token/IERC20.sol";
import "../utils/token/SafeERC20.sol";

contract Treasury is Operator {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address constant public USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    address public governance;
    address public riskOffPool;
    address public riskOnPool;


    uint256 public epoch;
    uint256 public startTime;
    uint256 public period = 24 hours;

    uint256 public riskOnPoolRatio;

    // flags
    bool public initialized = false;

    event Initialized(address indexed executor, uint256 at);
    event EpochUpdated(uint256 indexed atEpoch, uint256 timestamp);
    event CapacityUpdated(uint256 indexed atEpoch, uint256 _riskOffPoolCapacity, uint256 _riskOnPoolCapacity);

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

    receive () payable external {}

    function initialize(
        address _governance, 
        address _riskOffPool, 
        address _riskOnPool,
        uint256 _riskOnPoolRatio,
        uint256 _startTime
    ) public notInitialized {
        governance = _governance;
        riskOffPool = _riskOffPool;
        riskOnPool = _riskOnPool;
        riskOnPoolRatio = _riskOnPoolRatio;
        startTime = _startTime;
        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function buyGLP(
        address _GLPPool, 
        address _token, 
        uint256 _amount, 
        uint256 _minUsdg, 
        uint256 _minGlp
    ) public onlyGovernance {
        IGLPPool(_GLPPool).stakeByGov(_token, _amount, _minUsdg, _minGlp);
    }

    function sellGLP(
        address _GLPPool, 
        address _tokenOut, 
        uint256 _glpAmount, 
        uint256 _minOut, 
        address _receiver
    ) public onlyGovernance {
        IGLPPool(_GLPPool).withdrawByGov(_tokenOut, _glpAmount, _minOut, _receiver);
    }

    // send funds(ERC20 tokens) to pool
    function sendPoolFunds(address _pool, address _token, uint _amount) external onlyGovernance {
        require(_amount <= IERC20(_token).balanceOf(address(this)), "insufficient funds");
        IERC20(_token).safeTransfer(_pool, _amount);
    }

    function sendPoolFundsEth(address _pool, uint _amount) external onlyGovernance {
        require(_amount <= address(this).balance, "insufficient funds");
        payable(_pool).transfer(_amount);
    }

    // withdraw pool funds(ERC20 tokens) to specified address
    function withdrawPoolFunds(address _pool, address _token, uint256 _amount, address _to, bool _maximum) external onlyGovernance {
        if (_pool == riskOffPool && _token == USDC) {
            uint USDCAmount = IERC20(USDC).balanceOf(_pool);
            require(IGLPPool(_pool).getRequiredCollateral() + _amount <= IGLPPool(_pool).getStakedGLPUSDValue(_maximum) + USDCAmount, "cannot withdraw pool funds");
        }
        if (_pool == riskOnPool && _token == USDC) {
            uint USDCAmount = IERC20(USDC).balanceOf(_pool);
            require(IGLPPool(_pool).getRequiredCollateral() * riskOnPoolRatio / 100 + _amount <= IGLPPool(_pool).getStakedGLPUSDValue(_maximum) + USDCAmount, "cannot withdraw pool funds");
        }
        IGLPPool(_pool).treasuryWithdrawFunds(_token, _amount, _to);
    }

    // withdraw pool funds(ETH) to specified address
    function withdrawPoolFundsETH(address _pool, uint _amount, address _to) external onlyGovernance {
        require(_amount <= _pool.balance, "insufficient funds");
        IGLPPool(_pool).treasuryWithdrawFundsETH(_amount, _to);
    }

    // allocate reward at every epoch
    function allocateReward(address _riskOffPool, uint256 _amount) external onlyGovernance {
        IGLPPool(_riskOffPool).allocateReward(_amount);
    }

    // deposit funds from gov wallet to treasury
    function deposit(address _token, uint256 amount) external onlyGovernance {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), amount);
    }

    // withdraw funds from treasury to gov wallet
    function withdraw(address _token, uint256 amount) external onlyGovernance {
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    function withdrawETH(uint256 amount) external onlyGovernance {
        require(amount <= address(this).balance, "insufficient funds");
        payable(msg.sender).transfer(amount);
    }

    function handleStakeRequest(address _pool, address[] memory _address) external onlyGovernance {
        IGLPPool(_pool).handleStakeRequest(_address);
    }

    function handleWithdrawRequest(address _pool, address[] memory _address) external onlyGovernance {
        IGLPPool(_pool).handleWithdrawRequest(_address);
    }
    
    function handleRwards(
        address _pool,
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external onlyGovernance {
        IGLPPool(_pool).handleRwards(
            _shouldClaimGmx,
            _shouldStakeGmx,
            _shouldClaimEsGmx,
            _shouldStakeEsGmx,
            _shouldStakeMultiplierPoints,
            _shouldClaimWeth,
            _shouldConvertWethToEth);
    }

    function updateEpoch() external onlyGovernance {
        require(block.timestamp >= nextEpochPoint(), "Treasury: not opened yet");
        epoch += 1;
        IGLPPool(riskOffPool).resetCurrentEpochReward();
        IGLPPool(riskOnPool).resetCurrentEpochReward();
        emit EpochUpdated(epoch, block.timestamp);
    }

    function updateCapacity(uint _riskOffPoolCapacity, uint _riskOnPoolCapacity) external onlyGovernance {
        IGLPPool(riskOffPool).setCapacity(_riskOffPoolCapacity);
        IGLPPool(riskOnPool).setCapacity(_riskOnPoolCapacity);
        emit CapacityUpdated(epoch, _riskOffPoolCapacity, _riskOnPoolCapacity);
    } 
}