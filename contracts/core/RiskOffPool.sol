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

contract RiskOffPool is ShareWrapper, ContractGuard, Operator {

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
    uint256 public totalReward;
    uint256 public totalWithdrawRequest;

    // governance
    address public treasury;

    uint256 gasthreshold;
    uint256 minimumRequest;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

    mapping(address => StakeInfo) public stakeRequest;
    mapping(address => WithdrawInfo)public withdrawRequest;

    uint256 public withdrawLockupEpochs;

    uint256 public capacity;

    // flags
    bool public initialized = false;

    address public glpRouter = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    address public glpManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    address public RewardTracker = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;


    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event WithdrawRequest(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);

    /* ========== Modifiers =============== */

    modifier onlyTreasury() {
        require(treasury == msg.sender, "Boardroom: caller is not the treasury");
        _;
    }

    modifier memberExists() {
        require(balance_withdraw(msg.sender) > 0, "Boardroom: The member does not exist");
        _;
    }

    modifier notInitialized() {
        require(!initialized, "Boardroom: already initialized");
        _;
    }

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
        require(_withdrawLockupEpochs >= 0, "_withdrawLockupEpochs: out of range");
        withdrawLockupEpochs = _withdrawLockupEpochs;
    }

    function setFee(uint256 _fee) external onlyOperator {
        require(_fee >= 0 && _fee <= 10000, "fee: out of range");
        fee = _fee;
    }

    function setFeeTo(address _feeTo) external onlyOperator {
        feeTo = _feeTo;
    }

    function setCapacity(uint256 _capacity) external onlyTreasury {
        require(_capacity >= 0, "capacity: out of range");
        capacity = _capacity;
    }

    function setGlpRouter(address _glpRouter) external onlyOperator {
        glpRouter = _glpRouter;
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
        gasthreshold = _gasthreshold;
    }    

    function setMinimumRequest(uint256 _minimumRequest) external onlyOperator {
        minimumRequest = _minimumRequest;
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
    function getRequiredCollateral() public view returns (uint) {
        return _totalSupply.wait + _totalSupply.staked + _totalSupply.withdrawable + totalReward;
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
        return getGLPPrice(_maximum).mul(getStakedGLP()).div(1e48);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 _amount) public payable override onlyOneBlock {
        require(_amount >= minimumRequest, "stake out of range");
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
    }

    function exit(uint _glpAmount) external {
        require(withdrawRequest[msg.sender].requestTimestamp + ITreasury(treasury).period() * 5 <= block.timestamp, "cannot exit");
        uint amount = withdrawRequest[msg.sender].amount;
        IGLPRouter(glpRouter).unstakeAndRedeemGlp(USDC, _glpAmount, amount, address(this));
        _totalSupply.staked -= amount;
        _balances[msg.sender].staked -= amount;
        _totalSupply.withdrawable += amount;
        _balances[msg.sender].withdrawable += amount;
        delete withdrawRequest[msg.sender];
    }

    function handleStakeRequest(address[] memory _address) public onlyOneBlock onlyTreasury {
        uint256 _epoch = epoch();
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = stakeRequest[user].amount;
            updateReward(user);
            _balances[user].wait -= amount;
            _totalSupply.wait -= amount;
            _balances[user].staked += amount;
            _totalSupply.staked += amount;    
            totalWithdrawRequest -= amount;
            members[user].epochTimerStart = _epoch;  // reset timer   
            delete stakeRequest[user];
        }
    }

    function handleWithdrawRequest(address[] memory _address) public onlyOneBlock onlyTreasury {
        uint256 _epoch = epoch();
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = withdrawRequest[user].amount;
            uint reward = claimReward(user);
            totalReward -= reward;
            _balances[user].staked -= amount;
            _totalSupply.staked -= amount;
            _balances[user].withdrawable += amount;
            _totalSupply.withdrawable += amount;
            members[user].epochTimerStart = _epoch; // reset timer
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
            members[member].epochTimerStart = epoch(); // reset timer
            members[member].rewardEarned = 0;
            emit RewardPaid(member, reward);
        }
        return reward;
    }

    function stakeByGov(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) public onlyOneBlock onlyTreasury {
        require(_totalSupply.wait > 0, "Boardroom: Cannot stake 0");
        IERC20(_token).safeApprove(glpManager, 0);
        IERC20(_token).safeApprove(glpManager, _amount);
        IGLPRouter(glpRouter).mintAndStakeGlp(_token, _amount, _minUsdg, _minGlp);
        _totalSupply.wait -= _amount;
        _totalSupply.staked += _amount;
    }

/*
    function stakeByGovETH(uint256 amount, uint256 _minUsdg, uint256 _minGlp) public onlyOneBlock onlyTreasury {
        require(amount <= address(this).balance, "not enough funds");
        IGLPRouter(glpRouter).mintAndStakeGlpETH{value: amount}(_minUsdg, _minGlp);
    }
*/
    function withdrawByGov(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external onlyOneBlock onlyTreasury returns (uint256 amountOut) {
        require(_totalSupply.staked > 0, "Boardroom: Cannot withdraw 0");
        amountOut = IGLPRouter(glpRouter).unstakeAndRedeemGlp(_tokenOut, _glpAmount, _minOut, _receiver);
        _totalSupply.staked -= amountOut;
    }

/*
    function handleRwards() external onlyOneBlock onlyTreasury {

    }
*/
    function allocateReward(uint256 amount) external onlyOneBlock onlyTreasury {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(total_supply_staked() > 0, "Boardroom: Cannot allocate when totalSupply_staked is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(total_supply_staked()));

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS});
        boardroomHistory.push(newSnapshot);

        totalReward += amount;
        emit RewardAdded(msg.sender, amount);
    }

    function treasuryWithdrawFunds(address token, uint256 amount, address to) external onlyTreasury {
        IERC20(token).safeTransfer(to, amount);
    }

    function treasuryWithdrawFundsETH(uint256 amount, address to) external onlyTreasury {
        payable(to).transfer(amount);
    }

}