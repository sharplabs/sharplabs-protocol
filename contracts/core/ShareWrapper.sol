// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../utils/token/IERC20.sol";
import "../utils/token/SafeERC20.sol";
import "../utils/math/Abs.sol";

contract ShareWrapper {

    using SafeERC20 for IERC20;
    using Abs for int256;

    address constant public USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    uint256 public fee;
    address public feeTo;

    struct TotalSupply {
        uint256 wait;
        uint256 staked;
        uint256 withdrawable;
        int256 reward;
    }

    struct Balances {
        uint256 wait;
        uint256 staked;
        uint256 withdrawable;
        int256 reward;
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

    function total_supply_reward() public view returns (int256) {
        return _totalSupply.reward;
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

    function balance_reward(address account) public view returns (int256) {
        return _balances[account].reward;
    }

    function stake(uint256 amount) public payable virtual {
        _totalSupply.wait += amount;
        _balances[msg.sender].wait += amount;
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        require(_balances[msg.sender].withdrawable >= amount, "withdraw request greater than staked amount");
        if (balance_reward(msg.sender) > 0) {
            int256 _reward = _balances[msg.sender].reward;
            _balances[msg.sender].reward = 0;
            _totalSupply.reward -= _reward;
            IERC20(USDC).safeTransfer(msg.sender, _reward.abs());
        } else {
            int256 reward = _balances
        }
        _totalSupply.withdrawable -= amount;
        _balances[msg.sender].withdrawable -= amount;
        IERC20(USDC).safeTransfer(msg.sender, amount);
    }
}