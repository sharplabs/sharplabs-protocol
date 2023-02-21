// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/token/IERC20.sol";
import "../utils/token/SafeERC20.sol";

import "../utils/security/ContractGuard.sol";
import "../utils/access/Operator.sol";
import "../utils/interfaces/IGLPRouter.sol";
import "./ShareWrapper.sol";

contract Boardroom is ShareWrapper, ContractGuard, Operator {
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
        address account;
        uint256 amount;
        uint256 requestTimestamp;
        uint256 requestEpoch;
    }

    struct WithdralInfo {
        address account;
        uint256 amount;
        uint256 requestTimestamp;
        uint256 requestEpoch;
    }

    /* ========== STATE VARIABLES ========== */

    // governance
    address public governance;
    address public treasury;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;
    StakeInfo[] public stakeQueue;
    WithdralInfo[] public withdrawalQueue;

    uint256 public withdrawLockupEpochs;
    uint256 public rewardLockupEpochs;

    uint256 public capacity;

    uint256 public startTime;
    uint256 public epoch;
    uint256 public period = 8 hours;

    address public GLPRouter = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    address public GLPManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    address public USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;


    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);
    event BlacklistRewardPaid(address indexed from, address indexed to, uint256 reward);
    event BlacklistWithdrawn(address indexed from, address indexed to, uint256 amount);

    /* ========== Modifiers =============== */

    modifier onlyGovernance() {
        require(governance == msg.sender, "Boardroom: caller is not the governance");
        _;
    }

    modifier memberExists() {
        require(balance_withdraw(msg.sender) > 0, "Boardroom: The member does not exist");
        _;
    }

    /* ========== GOVERNANCE ========== */

    constructor (
        IERC20 _token,
        uint256 _fee,
        address _feeTo,
        address _governance,
        address _treasury
    ) {
        token = _token;
        fee = _fee;
        feeTo = _feeTo;
        governance = _governance;
        treasury = _treasury;
        startTime = block.timestamp;

        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: 0, rewardPerShare: 0});
        boardroomHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 1; // Lock for 6 epochs (48h) before release withdraw
        rewardLockupEpochs = 1; // Lock for 3 epochs (24h) before release claimReward

        IERC20(USDC).safeApprove(GLPRouter, type(uint).max);
        emit Initialized(msg.sender, block.number);
    }

    /* ========== CONFIG ========== */

    function setLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        require(_withdrawLockupEpochs >= _rewardLockupEpochs && _withdrawLockupEpochs <= 56, "_withdrawLockupEpochs: out of range"); // <= 2 week
        withdrawLockupEpochs = _withdrawLockupEpochs;
        rewardLockupEpochs = _rewardLockupEpochs;
    }

    function setFee(uint256 _fee) external onlyOperator {
        require(_fee >= 0 && _fee <= 10000, "out of range");
        fee = _fee;
    }

    function setFeeTo(address _feeTo) external onlyOperator {
        feeTo = _feeTo;
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
        return members[member].epochTimerStart.add(withdrawLockupEpochs) <= epoch;
    }

    function canClaimReward(address member) external view returns (bool) {
        return members[member].epochTimerStart.add(rewardLockupEpochs) <= epoch;
    }

    function nextEpochPoint() external view returns (uint256) {
        return startTime.add(epoch.mul(period));
    }

    // =========== Member getters

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address member) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(member).rewardPerShare;

        return balance_withdraw(member).mul(latestRPS.sub(storedRPS)).div(1e18).add(members[member].rewardEarned);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function updateReward(address member) public onlyOneBlock {
        if (member != address(0)) {
            Memberseat memory seat = members[member];
            seat.rewardEarned = earned(member);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            members[member] = seat;
        }
    }

    function stake(uint256 _amount) public override onlyOneBlock {
        require(_amount > 0, "Boardroom: Cannot stake 0");
        require(_totalSupply.staked + _amount <= capacity, "stake no capacity");
        updateReward(msg.sender);
        super.stake(_amount);
        StakeInfo memory newStake = StakeInfo({account: msg.sender, amount: _amount, requestTimestamp: block.timestamp, requestEpoch: epoch});
        stakeQueue.push(newStake);
        emit Staked(msg.sender, _amount);
    }

    function stakeByGov(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) public onlyOneBlock onlyGovernance {
        require(_totalSupply.wait > 0, "Boardroom: Cannot stake 0");
        IERC20(_token).safeApprove(GLPManager, 0);
        IERC20(_token).safeApprove(GLPManager, _amount);
        IGLPRouter(GLPRouter).mintAndStakeGlp(_token, _amount, _minUsdg, _minGlp);
        _totalSupply.staked += _amount;
        _totalSupply.wait -= _amount;
    }

    function handleStakeRequest() public onlyOneBlock onlyGovernance {
        uint length = stakeQueue.length;
        for (uint i = length - 1; i >= 0; i--) {
            _balances[stakeQueue[i].account].staked += stakeQueue[i].amount;
            _balances[stakeQueue[i].account].wait -= stakeQueue[i].amount;
            members[stakeQueue[i].account].epochTimerStart = epoch; // reset timer
            stakeQueue.pop();
        }
    }

    function withhdraw_request(uint256 _amount) external onlyOneBlock {
        WithdralInfo memory newWithdrawal = WithdralInfo({account: msg.sender, amount: _amount, requestTimestamp: block.timestamp, requestEpoch: epoch});
        withdrawalQueue.push(newWithdrawal);
        _totalSupply.withdraw += _amount;
    }

    function withdraw(uint256 amount) public override onlyOneBlock memberExists {
        require(amount > 0, "Boardroom: Cannot withdraw 0");
        require(members[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <= epoch, "Boardroom: still in withdraw lockup");
        updateReward(msg.sender);
        claimReward();
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balance_withdraw(msg.sender));
    }

    function withdrawByGov(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external onlyOneBlock onlyGovernance {
        require(_totalSupply.staked > 0, "Boardroom: Cannot withdraw 0");
        uint256 withdrawAmount = totalSupply_withdraw();
        IGLPRouter(GLPRouter).unstakeAndRedeemGlp(_tokenOut, _glpAmount, _minOut, _receiver);
        _totalSupply.staked -= withdrawAmount;
    }

    function handleWithdrawRequest() public onlyOneBlock onlyGovernance {
        uint length = withdrawalQueue.length;
        for (uint i = length - 1; i >= 0; i--) {
            _balances[withdrawalQueue[i].account].staked -= withdrawalQueue[i].amount;
            _balances[withdrawalQueue[i].account].withdraw += withdrawalQueue[i].amount;
            withdrawalQueue.pop();
        }
    }

    function claimReward() public {
        updateReward(msg.sender);
        uint256 reward = members[msg.sender].rewardEarned;
        if (reward > 0) {
            require(members[msg.sender].epochTimerStart.add(rewardLockupEpochs) <= epoch, "Boardroom: still in reward lockup");
            members[msg.sender].epochTimerStart = epoch; // reset timer
            members[msg.sender].rewardEarned = 0;
            token.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function receiveFundsAndReward(address _token, uint amount) public onlyOneBlock onlyGovernance {
        IERC20(_token).safeTransferFrom(governance, address(this), amount);
    }

    function allocateFunds(uint256 amount) external onlyOneBlock onlyGovernance {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(totalSupply_staked() > 0, "Boardroom: Cannot allocate when totalSupply_staked is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply_staked()));

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS});
        boardroomHistory.push(newSnapshot);

        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    function sendToTreasury(address _token, uint256 amount) external onlyGovernance {

    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        require(_to != address(0), "zero");
        // do not allow to drain core tokens
        require(address(_token) != address(token), "token");
        _token.safeTransfer(_to, _amount);
    }
}