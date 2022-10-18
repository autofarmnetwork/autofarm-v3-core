// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

type FlippedUint256 is uint256;

type FlippedUint128 is uint128;

/*
 * @example
 *
 * // Write to storage
 * s_myNum = FlippedUint256Lib.create(0);
 * // Reading from storage
 * myNum = s_myNum.get();
 */

library FlippedUint256Lib {
  function create(uint256 val) internal pure returns (FlippedUint256) {
    assembly {
      val := not(val)
    }
    return FlippedUint256.wrap(val);
  }

  function get(FlippedUint256 fuint) internal pure returns (uint256 val) {
    val = FlippedUint256.unwrap(fuint);
    if (val == 0) {
      return 0;
    }
    assembly {
      val := not(val)
    }
  }
}

library FlippedUint128Lib {
  function create(uint128 val) internal pure returns (FlippedUint128) {
    assembly {
      val := not(val)
    }
    return FlippedUint128.wrap(val);
  }

  function get(FlippedUint128 fuint) internal pure returns (uint128 val) {
    val = FlippedUint128.unwrap(fuint);
    if (val == 0) {
      return 0;
    }
    assembly {
      val := not(val)
    }
  }
}

using FlippedUint256Lib for FlippedUint256 global;
using FlippedUint128Lib for FlippedUint128 global;
