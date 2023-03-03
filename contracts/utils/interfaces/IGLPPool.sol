// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IGLPPool {

    function receiveFundsAndReward(
        address _token,
        uint _amount
    ) external;

    function stakeByGov(
        address _token, 
        uint256 _amount, 
        uint256 _minUsdg, 
        uint256 _minGlp
    ) external;

    function withdrawByGov(
        address _tokenOut, 
        uint256 _glpAmount, 
        uint256 _minOut, 
        address _receiver
    ) external;

    function total_supply_staked() external returns (uint);

    function handleStakeRequest(address[] memory _address) external;

    function handleWithdrawRequest(address[] memory _address) external;

    function allocateReward(uint256 _amount) external;

    function setCapacity(uint256 _amount) external;
}    
    