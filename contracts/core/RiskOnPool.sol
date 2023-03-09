// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/token/IERC20.sol";
import "../utils/token/SafeERC20.sol";

import "../utils/security/ContractGuard.sol";
import "../utils/access/Operator.sol";
import "../utils/interfaces/IGLPRouter.sol";
import "../utils/interfaces/ITreasury.sol";
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
    address public totalReward;

    // governance
    address public treasury;

    uint256 gasthreshold;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

 //   StakeInfo[] private stakeQueue;
 //   WithdralInfo[] private withdrawalQueue;
    mapping(address => StakeInfo) public StakeRequest;
    mapping(address => WithdrawInfo)public WithdrawRequest;

    uint256 public withdrawLockupEpochs;

    uint256 public capacity;

    // flags
    bool public initialized = false;

    address public glpRouter = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    address public glpManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;


    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);
    event BlacklistRewardPaid(address indexed from, address indexed to, uint256 reward);
    event BlacklistWithdrawn(address indexed from, address indexed to, uint256 amount);

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
        address _treasury
    ) public notInitialized {
        token = _token;
        fee = _fee;
        feeTo = _feeTo;
        gasthreshold = _gasthreshold;
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
        require(_fee >= 0 && _fee <= 10000, "out of range");
        fee = _fee;
    }

    function setFeeTo(address _feeTo) external onlyOperator {
        feeTo = _feeTo;
    }

    function setCapacity(uint256 _capacity) external onlyTreasury {
        capacity = _capacity;
    }

    function setGlpRouter(address _glpRouter) external onlyTreasury {
        glpRouter = _glpRouter;
    }

    function setGlpManager(address _glpManager) external onlyTreasury {
        glpManager = _glpManager;
    }

    function setTreasury(address _treasury) external onlyTreasury {
        treasury = _treasury;
    }

    function setGasThreshold(address _gasthreshold) external onlyTreasury {
        gasthreshold = _gasthreshold;
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

    function claimReward(address member) internal {
        updateReward(member);
        uint256 reward = members[member].rewardEarned;
        if (reward > 0) {
            members[member].epochTimerStart = epoch(); // reset timer
            members[member].rewardEarned = 0;
            token.safeTransfer(member, reward);
            emit RewardPaid(member, reward);
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 _amount) public payable override onlyOneBlock {
        require(_amount > 0, "Boardroom: Cannot stake 0");
        require(_totalSupply.staked + _totalSupply.wait + _amount <= capacity, "stake no capacity");
        super.stake(_amount);
        StakeInfo memory newStake = StakeInfo({amount: _amount, requestTimestamp: block.timestamp, requestEpoch: epoch()});
        StakeRequest[msg.sender][epoch()].push(newStake);
        emit Staked(msg.sender, _amount);
    }

    function withdraw_request(uint256 _amount) public payable onlyOneBlock {
        require(_amount > 0, "Boardroom: Cannot withdraw 0");
        require(members[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <= epoch(), "Boardroom: still in withdraw lockup");
        WithdrawInfo memory newWithdraw = WithdrawInfo({amount: _amount, requestTimestamp: block.timestamp, requestEpoch: epoch()});
        WithdrawRequest[msg.sender][epoch()].push(newWithdraw);
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

    function handleStakeRequest(address[] memory _address) public onlyOneBlock onlyTreasury {
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            StakeInfo[] memory stakeInfo = StakeRequest[user][epoch()];
            for(uint j = 0; j < stakeInfo.length; j++){
                uint amount = stakeInfo[j].amount;
                _balances[user].wait -= amount;
                _totalSupply.wait -= amount;
                _balances[user].staked += amount;
                _totalSupply.staked += amount;
                updateReward(user);
                members[user].epochTimerStart = epoch(); // reset timer
            }
            delete StakeRequest[user][epoch()];
        }
    }

    function handleWithdrawRequest(address[] memory _address) public onlyOneBlock onlyTreasury {
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            WithdrawInfo[] memory withdrawInfo = WithdrawRequest[user][epoch()];
            for(uint j = 0; j < withdrawInfo.length; j++){
                uint amount = withdrawInfo[j].amount;
                _balances[user].staked -= amount;
                _totalSupply.staked -= amount;
                _balances[user].withdraw += amount;
                _totalSupply.withdraw += amount;
                updateReward(user);
                claimReward(user);
                members[user].epochTimerStart = epoch(); // reset timer
            }
            delete WithdrawRequest[user][epoch()];
        }
    }

    function stakeByGov(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) public onlyOneBlock onlyTreasury {
        require(_totalSupply.wait > 0, "Boardroom: Cannot stake 0");
        IERC20(_token).safeApprove(glpManager, 0);
        IERC20(_token).safeApprove(glpManager, _amount);
        IGLPRouter(glpRouter).mintAndStakeGlp(_token, _amount, _minUsdg, _minGlp);
        _totalSupply.staked += _amount;
        _totalSupply.wait -= _amount;
    }

    function withdrawByGov(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external onlyOneBlock onlyTreasury {
        require(_totalSupply.staked > 0, "Boardroom: Cannot withdraw 0");
        IGLPRouter(glpRouter).unstakeAndRedeemGlp(_tokenOut, _glpAmount, _minOut, _receiver);
        _totalSupply.staked -= withdrawAmount;
    }

    function allocateReward(uint256 amount) external onlyOneBlock onlyTreasury {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(total_supply_staked() > 0, "Boardroom: Cannot allocate when totalSupply_staked is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(total_supply_staked()));

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS});
        boardroomHistory.push(newSnapshot);

        emit RewardAdded(msg.sender, amount);
    }
}