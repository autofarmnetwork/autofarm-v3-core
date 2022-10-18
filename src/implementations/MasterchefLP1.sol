// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SSTORE2Map} from "sstore2/SSTORE2Map.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import "../farms/StratX4_Masterchef.sol";
import {LP1Config, StratX4LibEarn} from "../libraries/StratX4LibEarn.sol";
import {Oracle} from "../libraries/Oracle.sol";

struct EarnConfig {
  address[] earnedAddresses;
  LP1Config[] compoundConfigs;
}

struct Earn1Config {
  address earnedAddress;
  LP1Config compoundConfig;
}

contract Strat is StratX4_Masterchef {
  address public immutable tokenBase;
  address public immutable tokenOther;

  constructor(
    address _asset,
    address _tokenBase,
    address _tokenOther,
    address _farmContractAddress,
    uint256 _pid,
    bytes4 _pendingRewardsSelector,
    address _feesController,
    uint256 _feeRate,
    Authority _authority,
    address[] memory _earnedAddresses,
    LP1Config[] memory _compoundConfigs
  )
    StratX4_Masterchef(_asset, _farmContractAddress, _pid, _feesController, _feeRate, _pendingRewardsSelector, _authority)
  {
    tokenBase = _tokenBase;
    tokenOther = _tokenOther;
    for (uint256 i; i < _earnedAddresses.length; i++) {
      SSTORE2Map.write(bytes32(uint256(uint160(_earnedAddresses[i]))), abi.encode(_compoundConfigs[i]));
    }
  }

  function harvest(address earnedAddress) internal override {}

  function compound(address earnedAddress, uint256 earnedAmount) internal override returns (uint256 profit) {
    Earn1Config memory _earnConfig =
      abi.decode(SSTORE2Map.read(bytes32(uint256(uint160(earnedAddress)))), (Earn1Config));

    profit += StratX4LibEarn.compoundLP1(
      asset, tokenBase, tokenOther, earnedAmount, ERC20(earnedAddress), _earnConfig.compoundConfig
    );
  }
}
