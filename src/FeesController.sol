// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Authority, Auth} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";

import {Uniswap} from "./libraries/Uniswap.sol";
import {SingleAUTOVault} from "./SAV.sol";

contract AutofarmFeesController is Auth {
  using SafeTransferLib for ERC20;
  using FixedPointMathLib for uint256;

  address public constant AUTOv2 = 0xa184088a740c695E156F91f5cC086a06bb78b827;
  address public treasury;
  address public SAV;
  address public votingController;
  uint8 public portionToPlatform;
  // portion to remaining fees after platform fees
  uint8 public portionToAUTOBurn;
  mapping(address => address) public rewardCfgPointers;

  struct RewardCfg {
    bool initialized;
    SwapConfig[] pathToAUTO;
  }

  struct SwapConfig {
    address pair;
    uint256 swapFee; // can change, make sure synced
    address tokenOut;
  }

  event FeeDistribution(address indexed earnedAddress, uint256 platformFee, uint256 burnFee, uint256 savFee);

  constructor(
    Authority _authority,
    address _treasury,
    address _votingController,
    uint8 _portionToPlatform,
    uint8 _portionToAUTOBurn
  ) Auth(address(0), _authority) {
    treasury = _treasury;
    votingController = _votingController;
    portionToPlatform = _portionToPlatform;
    portionToAUTOBurn = _portionToAUTOBurn;
  }

  function forwardFeesBulk(address[] calldata rewards, uint256[] calldata minAmountOuts) public requiresAuth {
    require(rewards.length == minAmountOuts.length, "lengths must be equal");
    for (uint256 i; i < rewards.length;) {
      forwardFees(ERC20(rewards[i]), minAmountOuts[i]);
      unchecked {
        i++;
      }
    }
  }

  function forwardFees(ERC20 earnedAddress, uint256 minAUTOOut) public requiresAuth {
    address rewardCfgPointer = rewardCfgPointers[address(earnedAddress)];
    require(rewardCfgPointer != address(0), "FeesController: RewardCfg uninitialized");
    RewardCfg memory rewardCfg = abi.decode(SSTORE2.read(rewardCfgPointer), (RewardCfg));
    require(rewardCfg.initialized, "FeesController: reward config not initialized");

    uint256 earnedAmt = earnedAddress.balanceOf(address(this));

    // Platform Fees

    uint256 feeToPlatform = earnedAmt.mulDivUp(portionToPlatform, uint256(type(uint8).max));
    require(feeToPlatform > 0, "FeesController: No fees to platform");
    require(feeToPlatform < earnedAmt, "FeesController: Fees to platform too large");

    earnedAmt -= feeToPlatform;
    earnedAddress.safeTransfer(treasury, feeToPlatform);

    // Buy AUTO then Burn / Send to SAV
    ERC20(earnedAddress).safeTransfer(rewardCfg.pathToAUTO[0].pair, earnedAmt);

    for (uint256 i; i < rewardCfg.pathToAUTO.length;) {
      SwapConfig memory swapConfig = rewardCfg.pathToAUTO[i];
      earnedAmt = Uniswap._swap(
        swapConfig.pair,
        swapConfig.swapFee,
        i == 0 ? address(earnedAddress) : rewardCfg.pathToAUTO[i - 1].tokenOut,
        i == rewardCfg.pathToAUTO.length - 1 ? AUTOv2 : swapConfig.tokenOut,
        earnedAmt,
        i == rewardCfg.pathToAUTO.length - 1 ? address(this) : rewardCfg.pathToAUTO[i + 1].pair
      );
      unchecked {
        i++;
      }
    }
    require(earnedAmt >= minAUTOOut, "FeesController: AUTO min amount not met");

    uint256 burnAmt = earnedAmt.mulDivDown(portionToAUTOBurn, type(uint8).max);
    ERC20(AUTOv2).safeTransfer(address(0), burnAmt);
    earnedAmt -= burnAmt;
    ERC20(AUTOv2).safeTransfer(SAV, earnedAmt);

    SingleAUTOVault(SAV).setProfitsVesting(earnedAmt);

    emit FeeDistribution(address(earnedAddress), feeToPlatform, burnAmt, earnedAmt);
  }

  /**
   * Setters
   */

  function setRewardCfg(address reward, SwapConfig[] calldata pathToAUTO) external requiresAuth {
    require(pathToAUTO.length > 0);
    require(pathToAUTO[pathToAUTO.length - 1].tokenOut == AUTOv2);
    RewardCfg memory rewardCfg = RewardCfg({pathToAUTO: pathToAUTO, initialized: true});
    rewardCfgPointers[reward] = SSTORE2.write(abi.encode(rewardCfg));
  }

  function setPortions(uint8 platform, uint8 burn) external requiresAuth {
    portionToPlatform = platform;
    portionToAUTOBurn = burn;
  }

  function setPortionsByVote(uint8 burn) external {
    require(msg.sender == votingController);
    portionToAUTOBurn = burn;
  }

  function setVotingController(address _votingController) external requiresAuth {
    votingController = _votingController;
  }

  function setTreasury(address _treasury) external requiresAuth {
    treasury = _treasury;
  }

  function setSAV(address _SAV) external requiresAuth {
    SAV = _SAV;
  }
}
