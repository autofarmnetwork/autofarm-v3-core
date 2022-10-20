// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../src/VenusDistribution.sol";

string constant CHAIN = "bsc";
bytes32 constant root =
  hex"6e595658f66ed2f89bcec957e459dc474d34bd2ff7c27f1a2d76ece8aaa3b047";
address constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
address constant AUTO = 0xa184088a740c695E156F91f5cC086a06bb78b827;

contract VenusDistributionUserTest is Test {
  AutofarmVenusDistributor public distributor;
  bytes32[] public proof;
  address[] public assets = new address[](10);

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl(CHAIN));
    assets[0] = BUSD;
    assets[1] = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c;
    assets[2] = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
    assets[3] = 0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD;
    assets[4] = 0x55d398326f99059fF775485246999027B3197955;
    assets[5] = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    assets[6] = 0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402;
    assets[7] = 0x47BEAd2563dCBf3bF2c9407fEa4dC236fAbA485A;
    assets[8] = 0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47;
    assets[9] = AUTO;

    distributor = new AutofarmVenusDistributor(
   	root,
   	payable(address(this)),
   	assets
   );

    proof = new bytes32[](14);
    proof[0] =
      hex"3d454f60ab695c67ac484c6064108020872d6ac796c65fda08a795c801609eef";
    proof[1] =
      hex"008ca16427ad84d8399c285b08ac6f1801b08e75933a544fdc68be6c3e5a043d";
    proof[2] =
      hex"73e6a867bebcfce35c687e53347202d122a36d9ba33a4f40f48ce105298d8258";
    proof[3] =
      hex"4b4dc0f7a95c8ddbe7e70857ec3e88f02e8e80fcc9ccd7d1b56d7cbb1bbc5bd9";
    proof[4] =
      hex"09fee0e43247e02e95fb75602138e647aa0b06638e2c4c56ccb597b439e6e258";
    proof[5] =
      hex"3c30397a1b1c87aebbecada2bfcc85046e91af22c5a4e7fe8a28025815279070";
    proof[6] =
      hex"7b2dc0d7c4a12245396dff96a6e5c5a6982df7b9d5a283db2eb73d5a40a1c746";
    proof[7] =
      hex"3a4a440e4d2cd205307d310fe7f470295b578bc67dea94b873be92a88d7e954b";
    proof[8] =
      hex"4b6b099a486202d52de90194fb47b4b6f225a460244fd33f8117bc3b479d932b";
    proof[9] =
      hex"754b6add2b488388c1e44c408efb33475310c63521b9ab5692302d256aec6200";
    proof[10] =
      hex"87b38edeedec79572ba94d61e1beff1f1d152a84890caa162d3cf3e93602f6d1";
    proof[11] =
      hex"7eea269bc9372b2018353f526396a15088d33b726ae3f6dcc23f3f13b4039d04";
    proof[12] =
      hex"d64850e272575ae207281c9416bb9c6e5a77279ee84e5faf1de2f26d1fa7e982";
    proof[13] =
      hex"5a86cb4bfbe0fba264ab2f3d6d733403e48ab83c04981832e6e2bb69b0de5d4e";
  }

  function testClaim() public {
    address claimant = 0xF482404f0Ee4bbC780199b2995A43882a8595adA;
    uint96[] memory amounts = new uint96[](10);

    amounts[0] = 886906295726567;
    amounts[1] = 102161828258;
    amounts[2] = 160514995479822;
    amounts[3] = 1347308579459;
    amounts[4] = 10062429340841016;
    amounts[5] = 12620767656655718748;
    amounts[6] = 10595479431167;
    amounts[7] = 561459275302425;
    amounts[8] = 12468978101101753;
    amounts[9] = 1090813448189014;

    deal(assets[0], address(distributor), amounts[0]);
    deal(assets[1], address(distributor), amounts[1]);
    deal(assets[2], address(distributor), amounts[2]);
    deal(assets[3], address(distributor), amounts[3]);
    deal(assets[4], address(distributor), amounts[4]);
    deal(assets[5], address(distributor), amounts[5]);
    deal(assets[6], address(distributor), amounts[6]);
    deal(assets[7], address(distributor), amounts[7]);
    deal(assets[8], address(distributor), amounts[8]);
    deal(assets[9], address(distributor), amounts[9]);
    vm.prank(claimant);
    distributor.claim(amounts, proof);
  }

  function testClaimFailWhenInsufficientBalance() public {
    address claimant = 0xF482404f0Ee4bbC780199b2995A43882a8595adA;
    uint96[] memory amounts = new uint96[](10);

    amounts[0] = 886906295726567;
    amounts[1] = 102161828258;
    amounts[2] = 160514995479822;
    amounts[3] = 1347308579459;
    amounts[4] = 10062429340841016;
    amounts[5] = 12620767656655718748;
    amounts[6] = 10595479431167;
    amounts[7] = 561459275302425;
    amounts[8] = 12468978101101753;
    amounts[9] = 1090813448189014;

    vm.expectRevert(bytes("TRANSFER_FAILED"));
    vm.prank(claimant);
    distributor.claim(amounts, proof);
  }

  function testClaimFailWhenInvalidAmount() public {
    address claimant = 0xF482404f0Ee4bbC780199b2995A43882a8595adA;
    uint96[] memory amounts = new uint96[](10);
    amounts[0] = 1e18;
    amounts[9] = 12436499489013;

    vm.expectRevert(bytes("AutofarmVenusDistributor: Invalid proof"));
    vm.prank(claimant);
    distributor.claim(amounts, proof);
  }

  function testClaimFailWhenInvalidAddress() public {
    address claimant = address(0);
    uint96[] memory amounts = new uint96[](10);

    amounts[0] = 886906295726567;
    amounts[1] = 102161828258;
    amounts[2] = 160514995479822;
    amounts[3] = 1347308579459;
    amounts[4] = 10062429340841016;
    amounts[5] = 12620767656655718748;
    amounts[6] = 10595479431167;
    amounts[7] = 561459275302425;
    amounts[8] = 12468978101101753;
    amounts[9] = 1090813448189014;

    deal(assets[0], address(distributor), amounts[0]);
    deal(assets[1], address(distributor), amounts[1]);
    deal(assets[2], address(distributor), amounts[2]);
    deal(assets[3], address(distributor), amounts[3]);
    deal(assets[4], address(distributor), amounts[4]);
    deal(assets[5], address(distributor), amounts[5]);
    deal(assets[6], address(distributor), amounts[6]);
    deal(assets[7], address(distributor), amounts[7]);
    deal(assets[8], address(distributor), amounts[8]);
    deal(assets[9], address(distributor), amounts[9]);
    vm.expectRevert(bytes("AutofarmVenusDistributor: Invalid proof"));
    vm.prank(claimant);
    distributor.claim(amounts, proof);
  }

  function testClaimFailWhenAlreadyClaimed() public {
    address claimant = 0xF482404f0Ee4bbC780199b2995A43882a8595adA;
    uint96[] memory amounts = new uint96[](10);

    amounts[0] = 886906295726567;
    amounts[1] = 102161828258;
    amounts[2] = 160514995479822;
    amounts[3] = 1347308579459;
    amounts[4] = 10062429340841016;
    amounts[5] = 12620767656655718748;
    amounts[6] = 10595479431167;
    amounts[7] = 561459275302425;
    amounts[8] = 12468978101101753;
    amounts[9] = 1090813448189014;

    deal(assets[0], address(distributor), amounts[0]);
    deal(assets[1], address(distributor), amounts[1]);
    deal(assets[2], address(distributor), amounts[2]);
    deal(assets[3], address(distributor), amounts[3]);
    deal(assets[4], address(distributor), amounts[4]);
    deal(assets[5], address(distributor), amounts[5]);
    deal(assets[6], address(distributor), amounts[6]);
    deal(assets[7], address(distributor), amounts[7]);
    deal(assets[8], address(distributor), amounts[8]);
    deal(assets[9], address(distributor), amounts[9]);

    vm.prank(claimant);
    distributor.claim(amounts, proof);

    vm.expectRevert(bytes("AutofarmVenusDistributor: Already claimed"));
    vm.prank(claimant);
    distributor.claim(amounts, proof);
  }
}

contract VenusDistributionAdminTest is Test {
  AutofarmVenusDistributor public distributor;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl(CHAIN));
    address[] memory assets = new address[](1);
    assets[0] = BUSD;
    distributor = new AutofarmVenusDistributor(
  	root,
  	payable(address(this)),
  	assets
  );
  }

  function testStopDistribution(uint96 amount) public {
    deal(BUSD, address(distributor), amount);
    assertEq(
      ERC20(BUSD).balanceOf(address(this)), 0, "Initial balance should be 0"
    );
    distributor.stopDistribution();
    assertEq(
      ERC20(BUSD).balanceOf(address(this)),
      amount,
      "Balance should be returned to owner"
    );
    // vm.roll(block.number + 1);
    // assertEq(address(distributor).code.length, 0, "Contract should be destroyed");
  }
}
