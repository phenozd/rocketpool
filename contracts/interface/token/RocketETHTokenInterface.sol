pragma solidity 0.6.8;

// SPDX-License-Identifier: GPL-3.0-only

import "./ERC20.sol";

interface RocketETHTokenInterface is ERC20 {
    function getExchangeRate() external view returns (uint256);
    function mint(uint256 _amount, address _to) external;
}
