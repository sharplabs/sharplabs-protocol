// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/token/IERC20.sol";
import "../utils/token/SafeERC20.sol";

contract ShareWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public token;

    uint256 public fee;
    address public feeTo;

    struct TotalSupply {
        uint256 wait;
        uint256 staked;
        uint256 withdrawable;
    }

    struct Balances {
        uint256 wait;
        uint256 staked;
        uint256 withdrawable;
    }

    mapping(address => Balances) internal _balances;
    TotalSupply internal _totalSupply;

    function total_supply_wait() public view returns (uint256) {
        return _totalSupply.wait;
    }

    function total_supply_staked() public view returns (uint256) {
        return _totalSupply.staked;
    }

    function total_supply_withdraw() public view returns (uint256) {
        return _totalSupply.withdrawable;
    }

    function balance_wait(address account) public view returns (uint256) {
        return _balances[account].wait;
    }

    function balance_staked(address account) public view returns (uint256) {
        return _balances[account].staked;
    }

    function balance_withdraw(address account) public view returns (uint256) {
        return _balances[account].withdrawable;
    }

    function stake(uint256 amount) public payable virtual {
        _totalSupply.wait += amount;
        _balances[msg.sender].wait += amount;
        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        require(_balances[msg.sender].withdrawable >= amount, "Boardroom: withdraw request greater than staked amount");
        _totalSupply.withdrawable -= amount;
        _balances[msg.sender].withdrawable -= amount;
        if (fee > 0) {
            uint tax = amount.mul(fee).div(10000);
            amount = amount.sub(tax);
            token.safeTransfer(feeTo, tax);
        }
        token.safeTransfer(msg.sender, amount);
    }
}