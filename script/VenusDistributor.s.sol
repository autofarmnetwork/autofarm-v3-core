// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "../src/VenusDistribution.sol";

contract VenusDistributionDeploymentScript is Script {
  function run() external {
    address[] memory assets = new address[](10);
    assets[0] = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    assets[1] = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c;
    assets[2] = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
    assets[3] = 0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD;
    assets[4] = 0x55d398326f99059fF775485246999027B3197955;
    assets[5] = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    assets[6] = 0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402;
    assets[7] = 0x47BEAd2563dCBf3bF2c9407fEa4dC236fAbA485A;
    assets[8] = 0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47;
    assets[9] = 0xa184088a740c695E156F91f5cC086a06bb78b827;

    vm.startBroadcast();

    AutofarmVenusDistributor distributor = new AutofarmVenusDistributor(
   	hex'06ee3bc42bc60fdd242b1c681b7c2a67175b5684b90e24a56dec8a36832bbcb8',
   	payable(0xF482404f0Ee4bbC780199b2995A43882a8595adA),
   	assets
    );

    vm.stopBroadcast();
  }
}
