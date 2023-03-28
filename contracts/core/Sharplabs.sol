// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/token/ERC20.sol";
import "../utils/access/Operator.sol";

contract Sharplabs is ERC20, Operator {

    address public riskOffPool;
    address public riskOnPool;

    // flags
    bool public initialized;
    bool public isTransferForbidden = true;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    event Initialized(address indexed executor, uint256 at);

    modifier notInitialized() {
        require(!initialized, "already initialized");
        _;
    }

    constructor() ERC20("Sharplabs", "Sharplabs"){
    }

    function initialize(address _riskOffPool, address _riskOnPool) public notInitialized {
        riskOffPool = _riskOffPool;
        riskOnPool = _riskOnPool;
        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function mint(address account, uint256 amount) external {
        require(msg.sender == riskOffPool || msg.sender == riskOnPool, "caller is not the pool");
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        require(msg.sender == riskOffPool || msg.sender == riskOnPool, "caller is not the pool");
        _burn(account, amount);
    }
    
    function _transfer(address from, address to, uint256 amount) internal override {
        require(!isTransferForbidden, "transfer is forbidden");
        super._transfer(from, to, amount);
    }

    function forbidTransfer() external onlyOperator {
        require(!isTransferForbidden, "transfer has been forbidden");
        isTransferForbidden = true;
    }

    function allowTransfer() external onlyOperator {
        require(isTransferForbidden, "transfer has been allowed");
        isTransferForbidden = false;
    }
}