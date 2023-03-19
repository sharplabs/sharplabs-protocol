// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;


contract Sharplabs {

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    address public riskOffPool;
    address public riskOnPool;

    // flags
    bool public initialized = false;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    event Initialized(address indexed executor, uint256 at);
    event Mint(address indexed from, address indexed to, uint256 value);
    event Burn(address indexed from, address indexed to, uint256 value);

    modifier notInitialized() {
        require(!initialized, "Boardroom: already initialized");
        _;
    }

    constructor() {
        _name = "Sharplabs";
        _symbol = "Sharplabs";
    }

    function initialize(address _riskOffPool, address _riskOnPool) public notInitialized {
        riskOffPool = _riskOffPool;
        riskOnPool = _riskOnPool;
        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function mint(address account, uint256 amount) external {
        require(msg.sender == riskOffPool || msg.sender == riskOnPool, "caller is not the pool");
        _mint(account, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Mint(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function burn(address account, uint256 amount) external {
        require(msg.sender == riskOffPool || msg.sender == riskOnPool, "caller is not the pool");
        _burn(account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

      emit Burn(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}