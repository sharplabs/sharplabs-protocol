// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/token/IERC20.sol";
import "../utils/token/SafeERC20.sol";
import "../utils/token/ISharplabs.sol";

import "../utils/security/ContractGuard.sol";
import "../utils/access/Operator.sol";
import "../utils/access/Blacklistable.sol";
import "../utils/security/Pausable.sol";

import "../utils/interfaces/IGLPRouter.sol";
import "../utils/interfaces/ITreasury.sol";
import "../utils/interfaces/IRewardTracker.sol";
import "../utils/interfaces/IGlpManager.sol";
import "../utils/math/Abs.sol";
import "./ShareWrapper.sol";

contract RiskOnPool is ShareWrapper, ContractGuard, Operator, Blacklistable, Pausable {

    using SafeERC20 for IERC20;
    using Address for address;
    using Abs for int256;

    /* ========== DATA STRUCTURES ========== */

    struct Memberseat {
        int256 rewardEarned;
        uint256 lastSnapshotIndex;
        uint256 epochTimerStart;
    }

    struct BoardroomSnapshot {
        int256 rewardReceived;
        int256 rewardPerShare;
        uint256 time;
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

    // reward
    int256 public currentEpochReward;
    uint256 public totalWithdrawRequest;

    address public token;
    address public treasury;

    uint256 public gasthreshold;
    uint256 public minimumRequest;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

    mapping(address => StakeInfo) public stakeRequest;
    mapping(address => WithdrawInfo) public withdrawRequest;

    uint256 public withdrawLockupEpochs;
    uint256 public userExitEpochs;

    uint256 public glpInFee;
    uint256 public glpOutFee;
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
    event RewardPaid(address indexed user, int256 reward);
    event RewardAdded(address indexed user, int256 reward);
    event Exit(address indexed user, uint256 amount);
    event StakeRequestIgnored(address indexed ignored, uint256 atEpoch);
    event WithdrawRequestIgnored(address indexed ignored, uint256 atEpoch);

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

    receive() payable external {}
    
    /* ========== GOVERNANCE ========== */

    function initialize (
        address _token,
        uint256 _fee,
        address _feeTo,
        uint256 _glpInFee,
        uint256 _glpOutFee,
        uint256 _gasthreshold,
        uint256 _minimumRequset,
        address _treasury
    ) public notInitialized {
        token = _token;
        fee = _fee;
        feeTo = _feeTo;
        glpInFee = _glpInFee;
        glpOutFee = _glpOutFee;
        gasthreshold = _gasthreshold;
        minimumRequest = _minimumRequset;
        treasury = _treasury;

        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: 0, rewardPerShare: 0});
        boardroomHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 2; // Lock for 2 epochs (48h) before release withdraw
        userExitEpochs = 5;

        initialized = true;

        emit Initialized(msg.sender, block.number);
    }

    /* ========== CONFIG ========== */

    function pause() external onlyTreasury {
        super._pause();
    }

    function unpause() external onlyTreasury {
        super._unpause();
    }

    function setLockUp(uint256 _withdrawLockupEpochs) external onlyOperator {
        require(_withdrawLockupEpochs > 0, "withdrawLockupEpochs must be greater than zero");
        withdrawLockupEpochs = _withdrawLockupEpochs;
    }

    function setExitEpochs(uint256 _userExitEpochs) external onlyOperator {
        require(_userExitEpochs > 0, "userExitEpochs must be greater than zero");
        userExitEpochs = _userExitEpochs;
    }

    function setFee(uint256 _fee) external onlyOperator {
        require(_fee >= 0 && _fee <= 10000, "fee: out of range");
        fee = _fee;
    }

    function setFeeTo(address _feeTo) external onlyOperator {
        require(_feeTo != address(0), "feeTo can not be zero address");
        feeTo = _feeTo;
    }

    function setCapacity(uint256 _capacity) external onlyTreasury {
        require(_capacity >= 0, "capacity must be greater than or equal to 0");
        capacity = _capacity;
    }

    function setGlpFee(uint256 _glpInFee, uint256 _glpOutFee) external onlyTreasury {
        require(_glpInFee >= 0 && _glpInFee <= 10000, "fee: out of range");
        require(_glpOutFee >= 0 && _glpOutFee <= 10000, "fee: out of range");
        _glpInFee = _glpInFee;
        glpOutFee = _glpOutFee;
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
        return boardroomHistory.length - 1;
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
        return members[member].epochTimerStart + withdrawLockupEpochs <= epoch();
    }

    function epoch() public view returns (uint256) {
        return ITreasury(treasury).epoch();
    }

    function nextEpochPoint() external view returns (uint256) {
        return ITreasury(treasury).nextEpochPoint();
    }
    // =========== Member getters

    function rewardPerShare() public view returns (int256) {
        return getLatestSnapshot().rewardPerShare;
    }

    // calculate earned reward of specified user
    function earned(address member) public view returns (int256) {
        int256 latestRPS = getLatestSnapshot().rewardPerShare;
        int256 storedRPS = getLastSnapshotOf(member).rewardPerShare;

        return int(balance_staked(member)) * (latestRPS - storedRPS) / 1e18 + members[member].rewardEarned;
    }

    // required usd collateral in the contract
    function getRequiredCollateral() public view returns (uint256) {
        if (_totalSupply.reward > 0) {
            return _totalSupply.wait + _totalSupply.staked + _totalSupply.withdrawable + _totalSupply.reward.abs();
        } else {
            return _totalSupply.wait + _totalSupply.staked + _totalSupply.withdrawable - _totalSupply.reward.abs();
        }
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
    function getStakedGLPUSDValue(bool _maximum) public view returns (uint256) {
        return getGLPPrice(_maximum) * getStakedGLP() / 1e42;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 _amount) public payable override onlyOneBlock notBlacklisted(msg.sender) whenNotPaused {
        require(_amount >= minimumRequest, "stake amount too low");
        require(_totalSupply.staked + _totalSupply.wait + _amount <= capacity, "stake no capacity");
        require(msg.value >= gasthreshold, "need more gas to handle request");
        if (fee > 0) {
            uint tax = _amount * fee / 10000;
            _amount = _amount - tax;
            IERC20(USDC).safeTransferFrom(msg.sender, feeTo, tax);
        }
        if (glpInFee > 0) {
            uint _glpInFee = _amount * glpInFee / 10000;
            _amount = _amount - _glpInFee;
            IERC20(USDC).safeTransferFrom(msg.sender, address(this), _glpInFee);
        }
        super.stake(_amount);
        stakeRequest[msg.sender].amount += _amount;
        stakeRequest[msg.sender].requestTimestamp = block.timestamp;
        stakeRequest[msg.sender].requestEpoch = epoch();
        ISharplabs(token).mint(msg.sender, _amount * 1e12);
        emit Staked(msg.sender, _amount);
    }

    function withdraw_request(uint256 _amount) external payable notBlacklisted(msg.sender) whenNotPaused {
        require(_amount >= minimumRequest, "withdraw amount too low");
        require(_amount + withdrawRequest[msg.sender].amount <= _balances[msg.sender].staked, "withdraw amount out of range");
        require(members[msg.sender].epochTimerStart + withdrawLockupEpochs <= epoch(), "Boardroom: still in withdraw lockup");
        require(msg.value >= gasthreshold, "need more gas to handle request");
        withdrawRequest[msg.sender].amount += _amount;
        withdrawRequest[msg.sender].requestTimestamp = block.timestamp;
        withdrawRequest[msg.sender].requestEpoch = epoch();
        totalWithdrawRequest += _amount;
        emit WithdrawRequest(msg.sender, _amount);
    }

    function withdraw(uint256 amount) public override onlyOneBlock memberExists notBlacklisted(msg.sender) whenNotPaused {
        require(amount != 0, "cannot withdraw 0");
        super.withdraw(amount);
        ISharplabs(token).burn(msg.sender, amount * 1e12);   
        emit Withdrawn(msg.sender, amount);
    }

    function redeem() external onlyOneBlock notBlacklisted(msg.sender) whenNotPaused {
        uint256 _epoch = epoch();
        require(_epoch == stakeRequest[msg.sender].requestEpoch, "can not redeem");
        uint amount = balance_wait(msg.sender);
        _totalSupply.wait -= amount;
        _balances[msg.sender].wait -= amount;
        IERC20(USDC).safeTransfer(msg.sender, amount);  
        ISharplabs(token).burn(msg.sender, amount * 1e12);   
        delete stakeRequest[msg.sender];
        emit Redeemed(msg.sender, amount);   
    }

    function exit() onlyOneBlock external notBlacklisted(msg.sender) whenNotPaused {
        require(withdrawRequest[msg.sender].requestTimestamp != 0, "no request");
        require(withdrawRequest[msg.sender].requestTimestamp + ITreasury(treasury).period() * userExitEpochs <= block.timestamp, "cannot exit");
        uint amount = _balances[msg.sender].staked;
        uint _glpAmount = amount * 1e42 / getGLPPrice(false);
        uint amountOut = IGLPRouter(glpRouter).unstakeAndRedeemGlp(USDC, _glpAmount, 0, address(this));
        require(amountOut <= amount, "withdraw overflow");
        _totalSupply.staked -= amount;
        _balances[msg.sender].staked -= amount;
        _totalSupply.withdrawable += amount;
        _balances[msg.sender].withdrawable += amount;
        delete withdrawRequest[msg.sender];
        emit Exit(msg.sender, amount);
    }

    function handleStakeRequest(address[] memory _address) external onlyTreasury {
        uint256 _epoch = epoch();
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = stakeRequest[user].amount;
            if (stakeRequest[user].requestEpoch == _epoch) { // check latest epoch
                emit StakeRequestIgnored(user, _epoch);
                continue;  
            }
            updateReward(user);
            _balances[user].wait -= amount;
            _balances[user].staked += amount;
            _totalSupply.wait -= amount;
            _totalSupply.staked += amount;    
            members[user].epochTimerStart = _epoch - 1;  // reset timer   
            delete stakeRequest[user];
        }
    }

    function handleWithdrawRequest(address[] memory _address) external onlyOneBlock onlyTreasury {
        uint256 _epoch = epoch();
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = withdrawRequest[user].amount;
            uint amountReceived = amount; // user real received amount
            if (withdrawRequest[user].requestEpoch == _epoch) { // check latest epoch
                emit WithdrawRequestIgnored(user, _epoch);
                continue;  
            }
            int reward = claimReward(user);
            if (glpOutFee > 0) {
                uint _glpOutFee = amount * glpOutFee / 10000;
                amountReceived = amount - _glpOutFee;
            }
            _balances[user].staked -= amount;
            _balances[user].withdrawable += amountReceived;
            _balances[user].reward += reward;
            _totalSupply.staked -= amount;
            _totalSupply.withdrawable += amountReceived;
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

    function claimReward(address member) internal returns (int) {
        updateReward(member);
        int256 reward = members[member].rewardEarned;
        if (reward > 0) {
            members[member].epochTimerStart = epoch() - 1; // reset timer
            members[member].rewardEarned = 0;
            _balances[msg.sender].reward += reward;
            emit RewardPaid(member, reward);
        }
        return reward;
    }

    function stakeByGov(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external onlyTreasury {
        IERC20(_token).safeApprove(glpManager, 0);
        IERC20(_token).safeApprove(glpManager, _amount);
        IGLPRouter(glpRouter).mintAndStakeGlp(_token, _amount, _minUsdg, _minGlp);
        emit StakedByGov(epoch(), _amount, block.timestamp);
    }

    function stakeETHByGov(uint256 amount, uint256 _minUsdg, uint256 _minGlp) external onlyTreasury {
        require(amount <= address(this).balance, "not enough funds");
        IGLPRouter(glpRouter).mintAndStakeGlpETH{value: amount}(_minUsdg, _minGlp);
        emit StakedETHByGov(epoch(), amount, block.timestamp);
    }

    function withdrawByGov(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external onlyTreasury {
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

    function allocateReward(int256 amount) external onlyOneBlock onlyTreasury {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(total_supply_staked() > 0, "Boardroom: Cannot allocate when totalSupply_staked is 0");

        // Create & add new snapshot
        int256 prevRPS = getLatestSnapshot().rewardPerShare;
        int256 nextRPS = prevRPS + amount * 1e18 / int(total_supply_staked());

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




