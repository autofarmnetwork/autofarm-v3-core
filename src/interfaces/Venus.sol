// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface IVToken is IERC20 {
  function underlying() external returns (address);
  function mint(uint256 mintAmount) external returns (uint256);
  function redeem(uint256 redeemTokens) external returns (uint256);
  function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
  function borrow(uint256 borrowAmount) external returns (uint256);
  function repayBorrow(uint256 repayAmount) external returns (uint256);
  function balanceOfUnderlying(address owner) external view returns (uint256);
  function borrowBalanceStored(address account) external view returns (uint256);
  function exchangeRateStored() external view returns (uint256);
  function borrowBalanceCurrent(address account) external returns (uint256);
  function exchangeRateCurrent() external returns (uint256);
}

interface IVenusUnitroller {
  function markets(address vTokenAddress)
    external
    view
    returns (bool, uint256, bool);
  function claimVenus(
    address[] memory holders,
    IVToken[] memory vTokens,
    bool borrowers,
    bool suppliers
  ) external;
  function enterMarkets(address[] memory _vtokens)
    external
    returns (uint256[] memory);
  function exitMarket(address _vtoken) external;
  function getAssetsIn(address account)
    external
    view
    returns (address[] memory);
  function getAccountLiquidity(address account)
    external
    view
    returns (uint256, uint256, uint256);
}
