// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "solmate/utils/MerkleProofLib.sol";
import "solmate/utils/SafeTransferLib.sol";
import "solmate/tokens/ERC20.sol";

contract AutofarmVenusDistributor {
  using SafeTransferLib for ERC20;

  address payable public immutable owner;
  bytes32 public immutable root;

  mapping(bytes32 => bool) public claimed;
  address[] public assets;

  event Claimed(address indexed receiver, address indexed asset, uint96 amount);

  constructor(bytes32 _root, address payable _owner, address[] memory _assets) {
    root = _root;
    owner = _owner;
    assets = _assets;
  }

  function claim(uint96[] calldata amounts, bytes32[] calldata proof) public {
    require(
      amounts.length == assets.length,
      "AutofarmVenusDistributor: amounts and assets mismatch"
    );
    bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amounts));

    require(!claimed[leaf], "AutofarmVenusDistributor: Already claimed");

    bool isValid = MerkleProofLib.verify(proof, root, leaf);
    require(isValid, "AutofarmVenusDistributor: Invalid proof");

    claimed[leaf] = true;

    for (uint256 i; i < amounts.length; i++) {
      if (amounts[i] == 0) {
        continue;
      }
      address asset = assets[i];

      ERC20(asset).safeTransfer(msg.sender, amounts[i]);

      emit Claimed(msg.sender, asset, amounts[i]);
    }
  }

  function stopDistribution() public {
    require(msg.sender == owner, "AutofarmVenusDistributor: UNAUTHORIZED");

    for (uint256 i; i < assets.length; i++) {
      ERC20 asset = ERC20(assets[i]);
      uint256 balance = asset.balanceOf(address(this));
      if (balance > 0) {
        asset.safeTransfer(msg.sender, balance);
      }
    }
    selfdestruct(payable(msg.sender));
  }

  function inCaseTokenGetStuck(address token, uint256 amount) public {
    require(msg.sender == owner, "AutofarmVenusDistributor: UNAUTHORIZED");

    ERC20(token).safeTransfer(msg.sender, amount);
  }
}
