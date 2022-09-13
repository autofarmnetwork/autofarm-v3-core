// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../src/VenusDistribution.sol";

string constant CHAIN = "bsc";
bytes32 constant root = hex"06ee3bc42bc60fdd242b1c681b7c2a67175b5684b90e24a56dec8a36832bbcb8";
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
    proof[0] = hex"c190faac8465a18bc5c8a6fcd417e94405b124e1cf3e82bf7aea3d470ca424ab";
    proof[1] = hex"11dedd32797c4346eea08118f35a4d97297a8be68a1a831ab86796634aa82a3d";
    proof[2] = hex"0bfff01a9a0b895be320f0f72d44933aa54438a1bec1e58f48d8c387a6e8456a";
    proof[3] = hex"05ca0b792bf841bafd33cd7fabab02e0403c0435b0521fc78177189f4a8edf6d";
    proof[4] = hex"ad6ad68fd9238ddae92cdd143aa2198f658aab0b06bd6de1de9a57c8fc8d7bc3";
    proof[5] = hex"9888934ebd736852f1a13a97ed1734888899bfb8cb96cd1ec9c254bc97ee0fce";
    proof[6] = hex"58de84fa2ff9a058842bfa4d0de136d48baf334a7acf348dd34dc50995a0ead1";
    proof[7] = hex"a2e5ba303e5edbe91e6b45fa4366523493bf739fc895a9789fab1675c5649c61";
    proof[8] = hex"04d6b4005ae38aba2c40757fb004fd3fa79633df3b7c70f4219e695898a65f48";
    proof[9] = hex"536c878b5020913bcb78fca9c48a41bc3f3927b086e33d4bbdb1210b15985ecc";
    proof[10] = hex"03e1ce8d0ae007257bba4740d13e943ef242ec65eea43fbc69cc186d57d2b981";
    proof[11] = hex"8892aa9e499b0814498d1ac66d5935ec998bf33aad7c38856f55e4aa5f40534a";
    proof[12] = hex"27697802204d2a394a85529373aba90d99de4564467a06ffe69c978e845137a4";
    proof[13] = hex"05b57770b5ef987a59c8c60ce19ab172513fc586930e0be172d2e40bf12638ea";
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
    amounts[9] = 978061096573322;

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
    distributor.claim(claimant, amounts, proof);
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
    amounts[9] = 978061096573322;

    vm.expectRevert(bytes("TRANSFER_FAILED"));
    distributor.claim(claimant, amounts, proof);
  }

  function testClaimFailWhenInvalidAmount() public {
    address claimant = 0xF482404f0Ee4bbC780199b2995A43882a8595adA;
    uint96[] memory amounts = new uint96[](10);
    amounts[0] = 1e18;
    amounts[9] = 12436499489013;

    vm.expectRevert(bytes("AutofarmVenusDistributor: Invalid proof"));
    distributor.claim(claimant, amounts, proof);
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
    amounts[9] = 978061096573322;

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
    distributor.claim(claimant, amounts, proof);
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
    amounts[9] = 978061096573322;

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

    distributor.claim(claimant, amounts, proof);

    vm.expectRevert(bytes("AutofarmVenusDistributor: Already claimed"));
    distributor.claim(claimant, amounts, proof);
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
    assertEq(ERC20(BUSD).balanceOf(address(this)), 0, "Initial balance should be 0");
    distributor.stopDistribution();
    assertEq(ERC20(BUSD).balanceOf(address(this)), amount, "Balance should be returned to owner");
    // vm.roll(block.number + 1);
    // assertEq(address(distributor).code.length, 0, "Contract should be destroyed");
  }
}
