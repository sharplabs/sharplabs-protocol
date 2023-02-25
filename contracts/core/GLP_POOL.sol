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
    address totalReward;

    // governance
    address public governance;
    address public treasury;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

 //   StakeInfo[] private stakeQueue;
 //   WithdralInfo[] private withdrawalQueue;
    mapping(address => StakeInfo[]) public StakeRequest;
    mapping(address => WithdrawInfo[]) public WithdrawRequest;

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

    function setCapacity(uint256 _capacity) external onlyOperator {
        capacity = _capacity;
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

    function updateReward(address member) public onlyOneBlock {
        if (member != address(0)) {
            Memberseat memory seat = members[member];
            seat.rewardEarned = earned(member);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            members[member] = seat;
        }
    }

    function claimReward() internal {
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

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 _amount) public override onlyOneBlock {
        require(_amount > 0, "Boardroom: Cannot stake 0");
        require(_totalSupply.staked + _amount <= capacity, "stake no capacity");
        super.stake(_amount);
        StakeInfo memory newStake = StakeInfo({amount: _amount, requestTimestamp: block.timestamp, requestEpoch: epoch});
        StakeRequest[msg.sender].push(newStake);
        emit Staked(msg.sender, _amount);
    }

    function withdraw_request(uint256 _amount) external onlyOneBlock {
        require(_amount > 0, "Boardroom: Cannot withdraw 0");
        require(members[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <= epoch, "Boardroom: still in withdraw lockup");
        WithdrawInfo memory newWithdraw = WithdrawInfo({amount: _amount, requestTimestamp: block.timestamp, requestEpoch: epoch});
        WithdrawRequest[msg.sender].push(newWithdraw);
    }

    function withdraw(uint256 amount) public override onlyOneBlock memberExists {
        require(amount != 0, "cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function redeem()external onlyOneBlock {
        uint amount = balance_wait(msg.sender);
        _totalSupply.wait -= amount;
        _balances[msg.sender].wait -= amount;
        token.safeTransfer(msg.sender, amount);        
    }

    function exit() external {
        withdraw(balance_withdraw(msg.sender));
    }

    function handleStakeRequest(address[] memory _address) public onlyOneBlock onlyGovernance {
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            StakeInfo[] memory stakeInfo = StakeRequest[user];
            for(uint j = 0; j < stakeInfo.length; j++){
                uint amount = stakeInfo[j].amount;
                _balances[user].wait -= amount;
                _totalSupply.wait -= amount;
                _balances[user].staked += amount;
                _totalSupply.staked += amount;
                updateReward(user);
                members[user].epochTimerStart = epoch; // reset timer
            }
            delete StakeRequest[user];
        }
    }

    function handleWithdrawRequest(address[] memory _address) public onlyOneBlock onlyGovernance {
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            WithdrawInfo[] memory withdrawInfo = WithdrawRequest[user];
            for(uint j = 0; j < withdrawInfo.length; j++){
                uint amount = withdrawInfo[j].amount;
                _balances[user].staked -= amount;
                _totalSupply.staked -= amount;
                _balances[user].withdraw += amount;
                _totalSupply.withdraw += amount;
                updateReward(user);
                claimReward();
                members[user].epochTimerStart = epoch; // reset timer
            }
            delete WithdrawRequest[user];
        }
    }

    function stakeByGov(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) public onlyOneBlock onlyGovernance {
        require(_totalSupply.wait > 0, "Boardroom: Cannot stake 0");
        IERC20(_token).safeApprove(GLPManager, 0);
        IERC20(_token).safeApprove(GLPManager, _amount);
        IGLPRouter(GLPRouter).mintAndStakeGlp(_token, _amount, _minUsdg, _minGlp);
        _totalSupply.staked += _amount;
        _totalSupply.wait -= _amount;
    }

    function withdrawByGov(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external onlyOneBlock onlyGovernance {
        require(_totalSupply.staked > 0, "Boardroom: Cannot withdraw 0");
        uint256 withdrawAmount = total_supply_withdraw();
        IGLPRouter(GLPRouter).unstakeAndRedeemGlp(_tokenOut, _glpAmount, _minOut, _receiver);
        _totalSupply.staked -= withdrawAmount;
    }

    function receiveFundsAndReward(address _token, uint amount) public onlyOneBlock onlyGovernance {
        IERC20(_token).safeTransferFrom(governance, address(this), amount);
    }

    function allocateFunds(uint256 amount) external onlyOneBlock onlyGovernance {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(total_supply_staked() > 0, "Boardroom: Cannot allocate when totalSupply_staked is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(total_supply_staked()));

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS});
        boardroomHistory.push(newSnapshot);

        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    function sendToTreasury(address _token, uint256 amount) external onlyGovernance {

    }

}