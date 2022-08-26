// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/*
 * SwapEncoder
 * Encodes swap parameters into dex swap calls
 * Might not be needed for uniswap swaps when we migrate to swapping through the pairs directly
 */

error UnknownSelector(bytes4 selector);

library SwapEncoder {
  uint256 constant SUBSWAP_MIN_OUT_AMOUNT = 1;
  uint256 constant SELECTORS_COUNT = 2;

  /**
   * Curve **
   */

  struct CurveSwapParams {
    int128 i;
    int128 j;
  }

  bytes4 constant CURVE_EXCHANGE = bytes4(keccak256("exchange(int128,int128,uint256,uint256)"));

  function encodeSwapCurve(uint256 amount, bytes memory data) internal pure returns (bytes memory) {
    CurveSwapParams memory params = abi.decode(data, (CurveSwapParams));
    return abi.encodeWithSelector(CURVE_EXCHANGE, params.i, params.j, amount, SUBSWAP_MIN_OUT_AMOUNT);
  }

  /**
   * Saddle **
   */

  struct SaddleSwapParams {
    uint256 deadline;
    uint8 i;
    uint8 j;
  }

  bytes4 constant SADDLE_SWAP = bytes4(keccak256("swap(uint8,uint8,uint256,uint256,uint256)"));

  function encodeSwapSaddle(uint256 amount, uint256 deadline, bytes memory data) internal pure returns (bytes memory) {
    SaddleSwapParams memory params = abi.decode(data, (SaddleSwapParams));
    return abi.encodeWithSelector(SADDLE_SWAP, params.i, params.j, amount, SUBSWAP_MIN_OUT_AMOUNT, deadline);
  }

  /**
   * Main encoder **
   */

  /*
  function encodeSwap(
    uint256 amount,
    address to,
    uint256 deadline,
    bytes4 selector,
    bytes memory data
  )
    internal
    pure
    returns (bytes memory)
  {
    // SELECTORS
    bytes4[SELECTORS_COUNT] memory selectors =
      [CURVE_EXCHANGE, SADDLE_SWAP];
    // ENCODERS
    function(bytes4,uint,address,uint, bytes memory)pure returns(bytes memory)[SELECTORS_COUNT]
      memory encoders =
        [_encodeSwapCurve, _encodeSwapSaddle];

    uint256 selectorIndex;
    bool selectorFound;
    for (uint256 i; i < SELECTORS_COUNT; i++) {
      if (selector == selectors[i]) {
        selectorFound = true;
        selectorIndex = i;
      }
    }
    if (!selectorFound) {
      revert UnknownSelector(selector);
    }
    return encoders[selectorIndex](
      selectors[selectorIndex], amount, to, deadline, data
    );
  }
	*/
}
