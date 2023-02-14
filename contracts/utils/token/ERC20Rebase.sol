// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "../Context.sol";
import "../math/SafeMath.sol";


contract ERC20Rebase is Context, IERC20, IERC20Metadata {

    using SafeMath for uint256;

    uint256 internal _gonsPerFragment;

    mapping(address => uint256) private _gonBalances;

    mapping(address => mapping(address => uint256)) private _allowedFragments;

    uint256 public TOTAL_GONS;

    uint256 internal _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor (string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @param _address The address to query.
     * @return The balance of the specified address.
     */
    function balanceOf(address _address) public view override returns (uint256) {
        if (_gonsPerFragment == 0) return 0;
        return _gonBalances[_address].div(_gonsPerFragment);
    }

    /**
     * @param _address The address to query.
     * @return The gon balance of the specified address.
     */
    function scaledBalanceOf(address _address) external view returns (uint256) {
        return _gonBalances[_address];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowedFragments[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowedFragments[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, _allowedFragments[owner][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = _allowedFragments[owner][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }
        return true;
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);        
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 gonValue = amount.mul(_gonsPerFragment);

        uint256 fromBalance = _gonBalances[from];
        require(fromBalance >= gonValue, "ERC20: transfer amount exceeds balance");
        unchecked {
            _gonBalances[from] = fromBalance - gonValue;
        }

        _gonBalances[to] += gonValue;    

        emit Transfer(from, to, amount);    
        
        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        uint256 gonValue = amount.mul(_gonsPerFragment);

        TOTAL_GONS += gonValue;
        _totalSupply += amount;
        _gonBalances[account] += gonValue;

        _afterTokenTransfer(address(0), account, amount);

        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 gonValue = amount.mul(_gonsPerFragment);
        uint256 accountBalance = _gonBalances[account];
        require(accountBalance >= gonValue, "ERC20: burn amount exceeds balance");    
        unchecked {
            _gonBalances[account] = accountBalance - gonValue;
        }

        TOTAL_GONS -= gonValue;
        _totalSupply -= amount;

        _afterTokenTransfer(account, address(0), amount);

        emit Transfer(account, address(0), amount);
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