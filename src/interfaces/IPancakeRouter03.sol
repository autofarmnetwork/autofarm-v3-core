pragma solidity >=0.8.13;

import "./IPancakeRouter01.sol";

interface IPancakeRouter03 is IPancakeRouter01 {
  function swapExactTokensForTokensSupportingFeeOnTransferTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    address referrer,
    uint256 deadline
  )
    external;
}