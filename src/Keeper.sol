// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Auth, Authority} from "solmate/auth/authorities/RolesAuthority.sol";

import {StratX4} from "./StratX4.sol";
import {AutofarmFeesController} from "./FeesController.sol";

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
  ) external requiresAuth returns (uint256[] memory profits) {
    require(strats.length == earnedAddresses.length);

    for (uint256 i; i < strats.length;) {
      try StratX4(strats[i]).earn(earnedAddresses[i], minAmountsOut[i])
      returns (uint256 profit) {
        profits[i] = profit;
      } catch {}
      i++;
    }
  }

  function batchCollectFees(
    address[] calldata strats,
    address[] calldata earnedAddresses
  ) external requiresAuth returns (uint256[] memory amounts) {
    require(strats.length == earnedAddresses.length);

    for (uint256 i; i < strats.length;) {
      try StratX4(strats[i]).collectFees(earnedAddresses[i]) returns (
        uint256 amount
      ) {
        amounts[i] = amount;
      } catch {}
      i++;
    }
  }

  function batchSetFeeRate(
    address[] calldata strats,
    uint256[] calldata feeRates
  ) external requiresAuth {
    require(strats.length == feeRates.length);

    for (uint256 i; i < strats.length;) {
      try StratX4(strats[i]).setFeeRate(feeRates[i]) {} catch {}
      i++;
    }
  }

  function batchForwardFees(
    address[] calldata earnedAddresses,
    uint256[] calldata minAmountsOut
  ) external requiresAuth {
    require(earnedAddresses.length == minAmountsOut.length);

    for (uint256 i; i < earnedAddresses.length;) {
      try AutofarmFeesController(feesController).forwardFees(
        earnedAddresses[i], minAmountsOut[i]
      ) {} catch {}
      i++;
    }
  }
}
