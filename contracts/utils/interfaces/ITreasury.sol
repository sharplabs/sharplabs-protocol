// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface ITreasury {
    function burn(uint256 amount) external;

    function burnFrom(address from, uint256 amount) external;

    function isOperator() external returns (bool);

    function operator() external view returns (address);

    function transferOperator(address newOperator_) external;

    function period() external view returns (uint256);
    
    function epoch() external view returns (uint256);

    function nextEpochPoint() external view returns (uint256);

    function getTokenPrice() external view returns (uint256);

    function getRealtimeTokenIndexPrice() external view returns (uint256);

    function initialize(address token, address share, address oracle, address boardroom, uint256 start_time) external;

    function allocateSeigniorage() external;

    function rebase() external returns (bool);

    function setInitialPrice(uint256 _initialEpochTokenIndexPrice) external returns (bool);
}