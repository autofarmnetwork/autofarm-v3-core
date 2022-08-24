// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SSTORE2} from "solmate/utils/SSTORE2.sol";

// Responsibilities:
// - Factory
// - call earn?
// - unify fees

import {FeeConfig} from "./StratX4.sol";
import {StratX4_Masterchef_LP1} from "./implementations/example.sol";

contract StratX4Controller {
  address public defaultFeeConfigPointer;

  event StratCreated();

  function createMasterchefStrat(
    address asset,
    address earnedAddress,
    address farmContractAddress,
    address pid
  )
    external
    returns (address strat)
  {
    bytes memory bytecode = type(StratX4_Masterchef_LP1).creationCode;
    bytes32 salt = keccak256(
      abi.encodePacked(
        asset, earnedAddress, farmContractAddress, pid, defaultFeeConfigPointer
      )
    );
    assembly {
      strat := create2(0, add(bytecode, 32), mload(bytecode), salt)
    }
    emit StratCreated();
  }

  function setDefaultFeeConfig(FeeConfig calldata _feeConfig) external {
    defaultFeeConfigPointer = SSTORE2.write(abi.encode(_feeConfig));
  }

  function createFeeConfig(FeeConfig calldata _feeConfig)
    external
    returns (address pointer)
  {
    pointer = SSTORE2.write(abi.encode(_feeConfig));
  }
}