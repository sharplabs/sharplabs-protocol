// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/token/IERC20.sol";
import "../utils/token/SafeERC20.sol";

import "../utils/security/ContractGuard.sol";
import "../utils/access/Operator.sol";
import "../utils/interfaces/IGLPRouter.sol";
import "../utils/interfaces/ITreasury.sol";
import "../utils/interfaces/IRewardTracker.sol";
import "../utils/interfaces/IGlpManager.sol";
import "./ShareWrapper.sol";

contract RiskOnPool is ShareWrapper, ContractGuard, Operator {

    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== DATA STRUCTURES ========== */

    struct Memberseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
        uint256 epochTimerStart;
    }

    struct BoardroomSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    struct StakeInfo {
        uint256 amount;
        uint256 requestTimestamp;
        uint256 requestEpoch;
    }

    struct WithdrawInfo {
        uint256 amount;
        uint256 requestTimestamp;
        uint256 requestEpoch;
    }

    /* ========== STATE VARIABLES ========== */

    address constant public USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    // reward
    uint256 public currentEpochReward;
    uint256 public totalWithdrawRequest;

    // governance
    address public treasury;

    uint256 gasthreshold;
    uint256 minimumRequest;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

    mapping(address => StakeInfo) public stakeRequest;
    mapping(address => WithdrawInfo) public withdrawRequest;

    uint256 public withdrawLockupEpochs;

    uint256 public capacity;

    // flags
    bool public initialized = false;

    address public glpRouter = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    address public rewardRouter = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
    address public glpManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    address public RewardTracker = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event WithdrawRequest(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);
    event StakedByGov(uint256 indexed atEpoch, uint256 amount, uint256 time);
    event StakedETHByGov(uint256 indexed atEpoch, uint256 amount, uint256 time);
    event WithdrawnByGov(uint256 indexed atEpoch, uint256 amount, uint256 time);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);
    event Exit(address indexed user, uint256 amount);

    /* ========== Modifiers =============== */

    modifier onlyTreasury() {
        require(treasury == msg.sender, "caller is not the treasury");
        _;
    }

    modifier memberExists() {
        require(balance_withdraw(msg.sender) > 0, "The member does not exist");
        _;
    }

    modifier notInitialized() {
        require(!initialized, "already initialized");
        _;
    }

    receive () payable external {}

    /* ========== GOVERNANCE ========== */

    function initialize (
        IERC20 _token,
        uint256 _fee,
        address _feeTo,
        uint256 _gasthreshold,
        uint256 _minimumRequset,
        address _treasury
    ) public notInitialized {
        token = _token;
        fee = _fee;
        feeTo = _feeTo;
        gasthreshold = _gasthreshold;
        minimumRequest = _minimumRequset;
        treasury = _treasury;

        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: 0, rewardPerShare: 0});
        boardroomHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 2; // Lock for 2 epochs (16h) before release withdraw

        initialized = true;

        emit Initialized(msg.sender, block.number);
    }

    /* ========== CONFIG ========== */

    function setLockUp(uint256 _withdrawLockupEpochs) external onlyOperator {
        require(_withdrawLockupEpochs >= 0, "withdrawLockupEpochs: below zero");
        withdrawLockupEpochs = _withdrawLockupEpochs;
    }

    function setFee(uint256 _fee) external onlyOperator {
        require(_fee >= 0 && _fee <= 10000, "fee: out of range");
        fee = _fee;
    }

    function setFeeTo(address _feeTo) external onlyOperator {
        require(_feeTo != address(0), "zero address");
        feeTo = _feeTo;
    }

    function setCapacity(uint256 _capacity) external onlyTreasury {
        require(_capacity >= 0, "capacity: below 0");
        capacity = _capacity;
    }

    function setRouter(address _glpRouter, address _rewardRouter) external onlyOperator {
        glpRouter = _glpRouter;
        rewardRouter = _rewardRouter;
    }

    function setGlpManager(address _glpManager) external onlyOperator {
        glpManager = _glpManager;
    }

    function setRewardTracker(address _RewardTracker) external onlyOperator {
        RewardTracker = _RewardTracker;
    }

    function setTreasury(address _treasury) external onlyOperator {
        treasury = _treasury;
    }

    function setGasThreshold(uint256 _gasthreshold) external onlyOperator {
        require(_gasthreshold >= 0, "gasthreshold below zero");
        gasthreshold = _gasthreshold;
    }    

    function setMinimumRequest(uint256 _minimumRequest) external onlyOperator {
        require(_minimumRequest >= 0, "minimumRequest below zero");
        minimumRequest = _minimumRequest;
    }   

    function resetCurrentEpochReward() external onlyTreasury {
        currentEpochReward = 0;
    }

    /* ========== VIEW FUNCTIONS ========== */

    // =========== Snapshot getters

    function latestSnapshotIndex() public view returns (uint256) {
        return boardroomHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (BoardroomSnapshot memory) {
        return boardroomHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address member) public view returns (uint256) {
        return members[member].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address member) internal view returns (BoardroomSnapshot memory) {
        return boardroomHistory[getLastSnapshotIndexOf(member)];
    }

    function canWithdraw(address member) external view returns (bool) {
        return members[member].epochTimerStart.add(withdrawLockupEpochs) <= epoch();
    }

    function epoch() public view returns (uint256) {
        return ITreasury(treasury).epoch();
    }

    function nextEpochPoint() external view returns (uint256) {
        return ITreasury(treasury).nextEpochPoint();
    }
    // =========== Member getters

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    // calculate earned reward of specified user
    function earned(address member) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(member).rewardPerShare;

        return balance_staked(member).mul(latestRPS.sub(storedRPS)).div(1e18).add(members[member].rewardEarned);
    }

    // required usd collateral in the contract
    function getRequiredCollateral() public view returns (uint256) {
        return _totalSupply.wait + _totalSupply.staked + _totalSupply.withdrawable + _totalSupply.reward;
    }

    // glp price
    function getGLPPrice(bool _maximum) public view returns (uint256) {
        return IGlpManager(glpManager).getPrice(_maximum);
    }

    // staked glp amount
    function getStakedGLP() public view returns (uint256) {
        return IRewardTracker(RewardTracker).balanceOf(address(this));
    }

    // staked glp usd value
    function getStakedGLPUSDValue(bool _maximum) public view returns (uint) {
        return getGLPPrice(_maximum).mul(getStakedGLP()).div(1e42);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 _amount) public payable override onlyOneBlock {
        require(_amount >= minimumRequest, "stake amount too low");
        require(_totalSupply.staked + _totalSupply.wait + _amount <= capacity, "stake no capacity");
        require(msg.value >= gasthreshold, "need more gas to handle request");
        super.stake(_amount);
        stakeRequest[msg.sender].amount += _amount;
        stakeRequest[msg.sender].requestTimestamp = block.timestamp;
        stakeRequest[msg.sender].requestEpoch = epoch();
        emit Staked(msg.sender, _amount);
    }

    function withdraw_request(uint256 _amount) public payable onlyOneBlock {
        require(_amount >= minimumRequest, "withdraw amount too low");
        require(_amount + withdrawRequest[msg.sender].amount <= _balances[msg.sender].staked, "withdraw amount out of range");
        require(members[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <= epoch(), "Boardroom: still in withdraw lockup");
        require(msg.value >= gasthreshold, "need more gas to handle request");
        withdrawRequest[msg.sender].amount += _amount;
        withdrawRequest[msg.sender].requestTimestamp = block.timestamp;
        withdrawRequest[msg.sender].requestEpoch = epoch();
        totalWithdrawRequest += _amount;
        emit WithdrawRequest(msg.sender, _amount);
    }

    function withdraw(uint256 amount) public override onlyOneBlock memberExists {
        require(amount != 0, "cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function redeem() external onlyOneBlock {
        uint amount = balance_wait(msg.sender);
        _totalSupply.wait -= amount;
        _balances[msg.sender].wait -= amount;
        token.safeTransfer(msg.sender, amount);     
        emit Redeemed(msg.sender, amount);   
    }


    function exit() external {
        require(withdrawRequest[msg.sender].requestTimestamp + ITreasury(treasury).period() * 5 <= block.timestamp, "cannot exit");
        uint amount = _balances[msg.sender].staked;
        uint _glpAmount = amount.mul(1e42).div(getGLPPrice(false));
        uint amountOut = IGLPRouter(glpRouter).unstakeAndRedeemGlp(USDC, _glpAmount, 0, address(this));
        require(amountOut <= amount, "withdraw overflow");
        _totalSupply.staked -= amount;
        _balances[msg.sender].staked -= amount;
        _totalSupply.withdrawable += amount;
        _balances[msg.sender].withdrawable += amount;
        delete withdrawRequest[msg.sender];
        emit Exit(msg.sender, amount);
    }


    function handleStakeRequest(address[] memory _address) public onlyOneBlock onlyTreasury {
        uint256 _epoch = epoch();
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = stakeRequest[user].amount;
            require(stakeRequest[user].requestEpoch == _epoch - 1, "wrong epoch"); // check latest epoch
            updateReward(user);
            _balances[user].wait -= amount;
            _balances[user].staked += amount;
            _totalSupply.wait -= amount;
            _totalSupply.staked += amount;    
            members[user].epochTimerStart = _epoch - 1;  // reset timer   
            delete stakeRequest[user];
        }
    }

    function handleWithdrawRequest(address[] memory _address) public onlyOneBlock onlyTreasury {
        uint256 _epoch = epoch();
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = withdrawRequest[user].amount;
            require(withdrawRequest[user].requestEpoch == _epoch - 1, "wrong epoch"); // check latest epoch
            uint reward = claimReward(user);
            _balances[user].staked -= amount;
            _balances[user].withdrawable += amount;
            _balances[user].reward += reward;
            _totalSupply.staked -= amount;
            _totalSupply.withdrawable += amount;
            currentEpochReward += reward;
            totalWithdrawRequest -= amount;
            members[user].epochTimerStart = _epoch - 1; // reset timer
            delete withdrawRequest[user];
        }
    }

    function updateReward(address member) internal {
        if (member != address(0)) {
            Memberseat memory seat = members[member];
            seat.rewardEarned = earned(member);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            members[member] = seat;
        }
    }

    function claimReward(address member) internal returns (uint) {
        updateReward(member);
        uint256 reward = members[member].rewardEarned;
        if (reward > 0) {
            members[member].epochTimerStart = epoch() - 1; // reset timer
            members[member].rewardEarned = 0;
            _balances[msg.sender].reward += reward;
            emit RewardPaid(member, reward);
        }
        return reward;
    }

    function stakeByGov(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) public onlyOneBlock onlyTreasury {
        IERC20(_token).safeApprove(glpManager, 0);
        IERC20(_token).safeApprove(glpManager, _amount);
        IGLPRouter(glpRouter).mintAndStakeGlp(_token, _amount, _minUsdg, _minGlp);
        emit StakedByGov(epoch(), _amount, block.timestamp);
    }

    function stakeETHByGov(uint256 amount, uint256 _minUsdg, uint256 _minGlp) public onlyOneBlock onlyTreasury {
        require(amount <= address(this).balance, "not enough funds");
        IGLPRouter(glpRouter).mintAndStakeGlpETH{value: amount}(_minUsdg, _minGlp);
        emit StakedETHByGov(epoch(), amount, block.timestamp);
    }

    function withdrawByGov(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) public onlyOneBlock onlyTreasury {
        IGLPRouter(glpRouter).unstakeAndRedeemGlp(_tokenOut, _glpAmount, _minOut, _receiver);
        emit WithdrawnByGov(epoch(), _minOut, block.timestamp);
    }

    function handleRwards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external onlyTreasury {
        IGLPRouter(rewardRouter).handleRwards(
            _shouldClaimGmx,
            _shouldStakeGmx,
            _shouldClaimEsGmx,
            _shouldStakeEsGmx,
            _shouldStakeMultiplierPoints,
            _shouldClaimWeth,
            _shouldConvertWethToEth);
    }

    function allocateReward(uint256 amount) external onlyOneBlock onlyTreasury {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(total_supply_staked() > 0, "Boardroom: Cannot allocate when totalSupply_staked is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(total_supply_staked()));

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS});
        boardroomHistory.push(newSnapshot);

        _totalSupply.reward += amount;
        emit RewardAdded(msg.sender, amount);
    }

    function treasuryWithdrawFunds(address _token, uint256 amount, address to) external onlyTreasury {
        IERC20(_token).safeTransfer(to, amount);
    }

    function treasuryWithdrawFundsETH(uint256 amount, address to) external onlyTreasury {
        payable(to).transfer(amount);
    }
}