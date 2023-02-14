// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/token/IERC20.sol";
import "../utils/token/SafeERC20.sol";

contract ShareWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public share;

    struct TotalSupply {
        uint256 wait;
        uint256 staked;
        uint256 withdraw;
    }

    struct Balances {
        uint256 wait;
        uint256 staked;
        uint256 withdraw;
    }

    mapping(address => Balances) internal _balances;
    TotalSupply internal _totalSupply;

    function totalSupply_wait() public view returns (uint256) {
        return _totalSupply.wait;
    }

    function totalSupply_staked() public view returns (uint256) {
        return _totalSupply.staked;
    }

    function totalSupply_withdraw() public view returns (uint256) {
        return _totalSupply.withdraw;
    }

    function balance_Wait(address account) public view returns (uint256) {
        return _balances[account].wait;
    }

    function balance_staked(address account) public view returns (uint256) {
        return _balances[account].staked;
    }

    function balance_withdraw(address account) public view returns (uint256) {
        return _balances[account].withdraw;
    }

    function stake(uint256 amount) public virtual {
        _totalSupply.wait = _totalSupply.wait.add(amount);
        _balances[msg.sender].wait = _balances[msg.sender].wait.add(amount);
        share.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        uint256 memberShare = _balances[msg.sender].withdraw;
        require(memberShare >= amount, "Boardroom: withdraw request greater than staked amount");
        _totalSupply.withdraw = _totalSupply.withdraw.sub(amount);
        _balances[msg.sender].withdraw = memberShare.sub(amount);
        share.safeTransfer(msg.sender, amount);
    }
}