// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Authority, Auth} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";

import {StratX4LibEarn, SwapRoute} from "./libraries/StratX4LibEarn.sol";

contract AutofarmFeesController is Auth {
  using SafeTransferLib for ERC20;
  using FixedPointMathLib for uint256;

  uint8 public constant MAX_BSC_PLATFORM_FEE = 64;
  address public constant AUTOv2 = 0xa184088a740c695E156F91f5cC086a06bb78b827;
  address public treasury;
  address public SAV;
  uint8 public portionToPlatform;
  // portion to remaining fees after platform fees
  uint8 public portionToAUTOBurn;
  mapping(address => address) public rewardCfgPointers;

  event FeeDistribution(
    address indexed earnedAddress,
    uint256 platformFee,
    uint256 burnFee,
    uint256 savFee
  );

  constructor(
    Authority _authority,
    address _treasury,
    address _sav,
    uint8 _portionToPlatform,
    uint8 _portionToAUTOBurn
  ) Auth(address(0), _authority) {
    treasury = _treasury;
    SAV = _sav;
    if (block.chainid != 56) {
      require(
        _portionToPlatform == type(uint8).max, "Platform fee on BSC is limited"
      );
    } else {
      require(
        _portionToPlatform <= MAX_BSC_PLATFORM_FEE,
        "Platform fee on BSC is limited"
      );
    }
    portionToPlatform = _portionToPlatform;
    portionToAUTOBurn = _portionToAUTOBurn;
  }

  function forwardFees(address earnedAddress, uint256 minAUTOOut)
    public
    requiresAuth
  {
    address rewardCfgPointer = rewardCfgPointers[address(earnedAddress)];
    require(
      rewardCfgPointer != address(0), "FeesController: RewardCfg uninitialized"
    );
    SwapRoute memory swapRoute =
      abi.decode(SSTORE2.read(rewardCfgPointer), (SwapRoute));

    uint256 earnedAmt = ERC20(earnedAddress).balanceOf(address(this));

    // Platform Fees

    uint256 feeToPlatform =
      earnedAmt.mulDivUp(portionToPlatform, uint256(type(uint8).max));
    require(feeToPlatform > 0, "FeesController: No fees to platform");
    require(
      feeToPlatform < earnedAmt, "FeesController: Fees to platform too large"
    );

    earnedAmt -= feeToPlatform;
    ERC20(earnedAddress).safeTransfer(treasury, feeToPlatform);

    earnedAmt = StratX4LibEarn.swapExactTokensForTokens(
      earnedAddress,
      earnedAmt,
      swapRoute.swapFees,
      swapRoute.pairsPath,
      swapRoute.tokensPath
    );

    require(earnedAmt >= minAUTOOut, "FeesController: AUTO min amount not met");

    uint256 burnAmt = earnedAmt.mulDivDown(portionToAUTOBurn, type(uint8).max);
    ERC20(AUTOv2).safeTransfer(address(0), burnAmt);
    earnedAmt -= burnAmt;
    ERC20(AUTOv2).safeTransfer(SAV, earnedAmt);

    emit FeeDistribution(earnedAddress, feeToPlatform, burnAmt, earnedAmt);
  }

  /**
   * Setters
   */

  function setRewardCfg(address reward, SwapRoute calldata route)
    external
    requiresAuth
  {
    require(route.pairsPath.length > 0);
    require(route.tokensPath.length == route.pairsPath.length);
    require(route.tokensPath.length == route.swapFees.length);
    require(route.tokensPath[route.tokensPath.length - 1] == AUTOv2);
    rewardCfgPointers[reward] = SSTORE2.write(abi.encode(route));
  }

  function setPlatformPortion(uint8 platform) external requiresAuth {
    portionToPlatform = platform;
  }

  function setBurnPortion(uint8 burn) external requiresAuth {
    if (block.chainid != 56) {
      revert("Invalid on non BSC chains");
    }
    portionToAUTOBurn = burn;
  }

  function setTreasury(address _treasury) external requiresAuth {
    if (block.chainid != 56) {
      revert("Invalid on non BSC chains");
    }
    treasury = _treasury;
  }

  function setSAV(address _SAV) external requiresAuth {
    SAV = _SAV;
  }
}
