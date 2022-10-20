// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/*
import "forge-std/Vm.sol";
import {LibString} from "solmate/utils/LibString.sol";

import {EarnConfig} from "../implementations/MasterchefLP1.sol";
import {SwapConfig, LP1Config} from "../libraries/StratX4LibEarn.sol";

struct CompoundConfigJson {
  address[] earnedToBasePathTokens;
  address[] earnedToBasePathPairs;
  uint256 pairSwapFee;
}

struct EarnConfigJson {
  CompoundConfigJson[] compoundConfigs;
  address[] earnedAddresses;
}

struct VaultDeployJson {
  address asset;
  EarnConfigJson earnConfig;
  address farmContractAddress;
  uint256 pid;
  address tokenBase;
  address tokenOther;
}

library LibVaultDeployJson {
  function loadVaultDeployJson(Vm vm, string memory json)
    internal
    returns (
      address asset,
      address farmContractAddress,
      address tokenBase,
      address tokenOther,
      uint256 pid,
      EarnConfig memory earnConfig
    )
  {
    return LibVaultDeployJson.mapVaultDeploy(abi.decode(vm.parseJson(json), (VaultDeployJson)));
  }

  function mapCompoundConfig(CompoundConfigJson memory compoundConfigJson)
    internal
    pure
    returns (LP1Config memory compoundConfig)
  {
    compoundConfig.pairSwapFee = compoundConfigJson.pairSwapFee;

    compoundConfig.earnedToBasePath = new SwapConfig[](compoundConfigJson.earnedToBasePathTokens.length);
    for (uint256 i; i < compoundConfig.earnedToBasePath.length; i++) {
      compoundConfig.earnedToBasePath[i] = SwapConfig({
        pair: compoundConfigJson.earnedToBasePathPairs[i],
        tokenOut: compoundConfigJson.earnedToBasePathTokens[i]
      });
    }
  }

  function mapEarnConfig(EarnConfigJson memory earnConfigJson) internal pure returns (EarnConfig memory earnConfig) {
    earnConfig.earnedAddresses = earnConfigJson.earnedAddresses;
    earnConfig.compoundConfigs = new LP1Config[](earnConfigJson.compoundConfigs.length);
    for (uint256 i; i < earnConfigJson.compoundConfigs.length; i++) {
      earnConfig.compoundConfigs[i] = LibVaultDeployJson.mapCompoundConfig(earnConfigJson.compoundConfigs[i]);
    }
  }

  function mapVaultDeploy(VaultDeployJson memory vaultDeployJson)
    internal
    pure
    returns (
      address asset,
      address farmContractAddress,
      address tokenBase,
      address tokenOther,
      uint256 pid,
      EarnConfig memory earnConfig
    )
  {
    earnConfig = LibVaultDeployJson.mapEarnConfig(vaultDeployJson.earnConfig);
    asset = vaultDeployJson.asset;
    farmContractAddress = vaultDeployJson.farmContractAddress;
    tokenBase = vaultDeployJson.tokenBase;
    tokenOther = vaultDeployJson.tokenOther;
    pid = vaultDeployJson.pid;
  }
}
*/
