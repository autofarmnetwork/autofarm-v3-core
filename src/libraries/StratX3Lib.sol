// SPDX-License-Identifier: MIT

pragma solidity >=0.8.13;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import "../interfaces/IPancakeRouter01.sol";
import "../interfaces/IPancakeRouter02.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/tokens/WETH.sol";
import "solmate/utils/SafeTransferLib.sol";

interface IReward {
  function updateRewards(
    address userAddress,
    uint256 sharesChange,
    bool isSharesRemoved
  )
    external;
}

library StratX3Lib {
  using SafeTransferLib for ERC20;
  using FixedPointMathLib for uint256;

  event SetSettings(
    uint256 _entranceFeeFactor,
    uint256 _withdrawFeeFactor,
    uint256 _controllerFee,
    uint256 _buyBackRate,
    uint256 _slippageFactor
  );

  function _harvestReward(
    address[] memory rewarders,
    address _userAddress,
    uint256 _sharesChange,
    bool _isSharesRemoved
  )
    internal
  {
    for (uint256 i = 0; i < rewarders.length; i++) {
      IReward(rewarders[i]).updateRewards(
        _userAddress, _sharesChange, _isSharesRemoved
      );
    }
  }

  /*
  function checkSetSettings(
    uint256 _entranceFeeFactor,
    uint256 entranceFeeFactorLL,
    uint256 entranceFeeFactorMax,
    uint256 _withdrawFeeFactor,
    uint256 withdrawFeeFactorLL,
    uint256 withdrawFeeFactorMax,
    uint256 _controllerFee,
    uint256 controllerFeeUL,
    uint256 _buyBackRate,
    uint256 _slippageFactor,
    uint256 slippageFactorUL
  )
    internal
    returns (bool)
  {
    require(
      _entranceFeeFactor >= entranceFeeFactorLL, "_entranceFeeFactor too low"
    );
    require(
      _entranceFeeFactor <= entranceFeeFactorMax, "_entranceFeeFactor too high"
    );
    require(
      _withdrawFeeFactor >= withdrawFeeFactorLL, "_withdrawFeeFactor too low"
    );
    require(
      _withdrawFeeFactor <= withdrawFeeFactorMax, "_withdrawFeeFactor too high"
    );
    require(_controllerFee <= controllerFeeUL, "_controllerFee too high");

    // require(_buyBackRate <= buyBackRateUL, "_buyBackRate too high");
    // buyBackRate = _buyBackRate;

    require(_slippageFactor <= slippageFactorUL, "_slippageFactor too high");

    emit SetSettings(
      _entranceFeeFactor,
      _withdrawFeeFactor,
      _controllerFee,
      _buyBackRate,
      _slippageFactor
      );

    return true;
  }

  // function convertDustToEarned() public virtual whenNotPaused {
  //     require(isAutoComp, "!isAutoComp");
  //     require(!isCAKEStaking, "isCAKEStaking");

  //     // Converts dust tokens into earned tokens, which will be reinvested on the next earn().

  //     // Converts token0 dust (if any) to earned tokens
  //     uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
  //     if (token0Address != earnedAddress && token0Amt > 0) {
  //         IERC20(token0Address).safeIncreaseAllowance(
  //             uniRouterAddress,
  //             token0Amt
  //         );

  //         // Swap all dust tokens to earned tokens
  //         _safeSwap(
  //             uniRouterAddress,
  //             token0Amt,
  //             slippageFactor,
  //             token0ToEarnedPath,
  //             address(this),
  //             block.timestamp.add(600)
  //         );
  //     }

  //     // Converts token1 dust (if any) to earned tokens
  //     uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
  //     if (token1Address != earnedAddress && token1Amt > 0) {
  //         IERC20(token1Address).safeIncreaseAllowance(
  //             uniRouterAddress,
  //             token1Amt
  //         );

  //         // Swap all dust tokens to earned tokens
  //         _safeSwap(
  //             uniRouterAddress,
  //             token1Amt,
  //             slippageFactor,
  //             token1ToEarnedPath,
  //             address(this),
  //             block.timestamp.add(600)
  //         );
  //     }
  // }
  //
  */
}