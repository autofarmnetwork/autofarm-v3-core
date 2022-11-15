// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Auth, Authority} from "solmate/auth/Auth.sol";

interface IAutofarmFeesController {
  function forwardFees(address earnedAddress, uint256 minAUTOOut) external;
}

interface IStratX4 {
  function earn(address earnedAddress, uint256 minAmountOut)
    external
    returns (uint256 profit, uint256 earnedAmount, uint256 feeCollected);
  function collectFees(address earnedAddress) external returns (uint256 amount);
  function setFeeRate(uint256 _feeRate) external;
}

contract Keeper is Auth {
  address public immutable feesController;

  constructor(address _feesController, Authority _authority)
    Auth(address(0), _authority)
  {
    feesController = _feesController;
  }

  function batchEarn(
    address[] calldata strats,
    address[] calldata earnedAddresses,
    uint256[] calldata minAmountsOut
  )
    external
    requiresAuth
    returns (
      uint256[] memory profits,
      uint256[] memory earnedAmounts,
      uint256[] memory feesCollected
    )
  {
    require(
      strats.length == earnedAddresses.length, "Input arrays length mismatch"
    );
    require(
      strats.length == minAmountsOut.length, "Input arrays length mismatch"
    );

    profits = new uint256[](strats.length);
    earnedAmounts = new uint256[](strats.length);
    feesCollected = new uint256[](strats.length);

    for (uint256 i; i < strats.length;) {
      try IStratX4(strats[i]).earn(earnedAddresses[i], minAmountsOut[i])
      returns (uint256 profit, uint256 earnedAmount, uint256 feeCollected) {
        profits[i] = profit;
        earnedAmounts[i] = earnedAmount;
        feesCollected[i] = feeCollected;
      } catch {}

      unchecked {
        i++;
      }
    }
  }

  function batchCollectFees(
    address[] calldata strats,
    address[] calldata earnedAddresses
  ) external requiresAuth returns (uint256[] memory amounts) {
    require(strats.length == earnedAddresses.length);

    amounts = new uint256[](strats.length);

    for (uint256 i; i < strats.length;) {
      try IStratX4(strats[i]).collectFees(earnedAddresses[i]) returns (
        uint256 amount
      ) {
        amounts[i] = amount;
      } catch {}

      unchecked {
        i++;
      }
    }
  }

  function batchSetFeeRate(
    address[] calldata strats,
    uint256[] calldata feeRates
  ) external requiresAuth {
    require(strats.length == feeRates.length);

    for (uint256 i; i < strats.length;) {
      try IStratX4(strats[i]).setFeeRate(feeRates[i]) {} catch {}

      unchecked {
        i++;
      }
    }
  }

  function batchForwardFees(
    address[] calldata earnedAddresses,
    uint256[] calldata minAmountsOut
  ) external requiresAuth {
    require(earnedAddresses.length == minAmountsOut.length);

    for (uint256 i; i < earnedAddresses.length;) {
      try IAutofarmFeesController(feesController).forwardFees(
        earnedAddresses[i], minAmountsOut[i]
      ) {} catch {}

      unchecked {
        i++;
      }
    }
  }
}
