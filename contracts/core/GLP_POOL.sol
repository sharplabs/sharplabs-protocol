// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/token/IERC20.sol";
import "../utils/token/SafeERC20.sol";

import "../utils/security/ContractGuard.sol";
import "../utils/interfaces/IGLPRouter.sol";
import "./ShareWrapper.sol";

contract Boardroom is ShareWrapper, ContractGuard {
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

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;
    address public governance;

    IERC20 token;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

    uint256 public withdrawLockupEpochs;
    uint256 public rewardLockupEpochs;

    uint256 public fee;
    address public feeTo;

    uint256 public startTime;
    uint256 public epoch;
    uint256 public period = 8 hours;

    address public GLPRouter = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
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

    modifier onlyOperator() {
        require(operator == msg.sender, "Boardroom: caller is not the operator");
        _;
    }

    modifier onlyGovernance() {
        require(governance == msg.sender, "Boardroom: caller is not the governance");
        _;
    }

    modifier memberExists() {
        require(balance_withdraw(msg.sender) > 0, "Boardroom: The member does not exist");
        _;
    }

    modifier updateReward(address member) {
        if (member != address(0)) {
            Memberseat memory seat = members[member];
            seat.rewardEarned = earned(member);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            members[member] = seat;
        }
        _;
    }

    /* ========== GOVERNANCE ========== */

    constructor (
        IERC20 _token,
        IERC20 _share,
        uint256 _fee,
        address _feeTo,
        address _governance
    ) {
        token = _token;
        share = _share;
        fee = _fee;
        feeTo = _feeTo;
        governance = _governance;
        startTime = block.timestamp;

        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: 0, rewardPerShare: 0});
        boardroomHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 6; // Lock for 6 epochs (48h) before release withdraw
        rewardLockupEpochs = 3; // Lock for 3 epochs (24h) before release claimReward

        IERC20(USDC).safeApprove(GLPRouter, type(uint).max);
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

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

    function stake(uint256 amount) public override onlyOneBlock updateReward(msg.sender) {
        require(amount > 0, "Boardroom: Cannot stake 0");
        super.stake(amount);
        members[msg.sender].epochTimerStart = epoch; // reset timer
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override onlyOneBlock memberExists updateReward(msg.sender) {
        require(amount > 0, "Boardroom: Cannot withdraw 0");
        require(members[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <= epoch, "Boardroom: still in withdraw lockup");
        claimReward();
        if (fee > 0) {
            uint tax = amount.mul(fee).div(10000);
            amount = amount.sub(tax);
            share.safeTransferFrom(msg.sender, feeTo, tax);
        }
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function withhdraw_request(uint256 amount) public virtual returns (bool) {
//                _totalSupply = _totalSupply.sub(amount);

    }

    function exit() external {
        withdraw(balance_withdraw(msg.sender));
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = members[msg.sender].rewardEarned;
        if (reward > 0) {
            require(members[msg.sender].epochTimerStart.add(rewardLockupEpochs) <= epoch, "Boardroom: still in reward lockup");
            members[msg.sender].epochTimerStart = epoch; // reset timer
            members[msg.sender].rewardEarned = 0;
            token.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function stakeByGov(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external onlyOneBlock onlyGovernance {
        require(_totalSupply.wait > 0, "Boardroom: Cannot stake 0");
        IERC20(_token).safeApprove(GLPRouter, type(uint).max);
        IGLPRouter(GLPRouter).mintAndStakeGlp(_token, _amount, _minUsdg, _minGlp);
    }

    function allocateReward(uint256 amount) external onlyOneBlock onlyGovernance {
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

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        require(_to != address(0), "zero");
        // do not allow to drain core tokens
        require(address(_token) != address(token), "token");
        require(address(_token) != address(share), "share");
        _token.safeTransfer(_to, _amount);
    }
}