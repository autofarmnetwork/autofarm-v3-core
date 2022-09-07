// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC1155} from "solmate/tokens/ERC1155.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/// @notice Locking Vault based on Solmate ERC4626 implementation.
/// @author fmnxl (https://github.com/fmnxl/locking-vault/blob/main/src/LockingVault.sol)
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/mixins/ERC4626.sol)

abstract contract LockingVault is ERC1155 {
  using SafeTransferLib for ERC20;
  using FixedPointMathLib for uint256;

  /*//////////////////////////////////////////////////////////////
                                 EVENTS
  //////////////////////////////////////////////////////////////*/

  event Stake(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
  event Unstake(
    address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
  );
  event Unlock(
    address indexed caller, address indexed receiver, address indexed owner, uint256 assets
  );

  /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
  //////////////////////////////////////////////////////////////*/

  ERC20 public immutable asset;

  /*//////////////////////////////////////////////////////////////
                                MUTABLES
  //////////////////////////////////////////////////////////////*/

  uint256 public totalShareSupply;
  uint256 public currentReceiptId;

  constructor(ERC20 _asset) {
    asset = _asset;
  }

  /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
  //////////////////////////////////////////////////////////////*/

  function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
    // Check for rounding error since we round down in previewDeposit.
    require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

    // Need to transfer before minting or ERC777s could reenter.
    asset.safeTransferFrom(msg.sender, address(this), assets);

    _mintShare(receiver, shares);

    emit Stake(msg.sender, receiver, assets, shares);

    afterDeposit(assets, shares);
  }

  function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
    assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

    // Need to transfer before minting or ERC777s could reenter.
    asset.safeTransferFrom(msg.sender, address(this), assets);

    _mintShare(receiver, shares);

    emit Stake(msg.sender, receiver, assets, shares);

    afterDeposit(assets, shares);
  }

  function withdraw(uint256 assets, address receiver, address owner) public virtual returns (uint256 shares) {
    shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

    if (msg.sender != owner) {
      require(isApprovedForAll[owner][msg.sender]);
    }

    beforeWithdraw(assets, shares);

    _burnShare(owner, shares);

    uint256 _newId = currentReceiptId++;
    _mintReceipt(receiver, _newId, assets, "");
    afterMintReceipt(_newId, assets);

    emit Unstake(msg.sender, receiver, owner, assets, shares);
  }

  function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256 assets) {
    if (msg.sender != owner) {
      require(isApprovedForAll[owner][msg.sender]);
    }

    // Check for rounding error since we round down in previewRedeem.
    require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

    beforeWithdraw(assets, shares);

    _burnShare(owner, shares);

    uint256 _newId = currentReceiptId++;
    _mintReceipt(receiver, _newId, assets, "");
    afterMintReceipt(_newId, assets);

    emit Unstake(msg.sender, receiver, owner, assets, shares);
  }

  /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
  //////////////////////////////////////////////////////////////*/

  function afterMintReceipt(uint256 id, uint256 assets) internal virtual;

  function unlockableAssets(uint256 id) internal virtual returns (uint256);

  function unlockAssets(uint256 id, address receiver, address owner) public virtual returns (uint256 assets) {
    if (msg.sender != owner) {
      require(isApprovedForAll[owner][msg.sender]);
    }

    require((assets = unlockableAssets(id)) != 0, "ZERO_ASSETS");

    _burnReceipt(msg.sender, id, assets);

    asset.safeTransfer(msg.sender, assets);

    emit Unlock(msg.sender, receiver, owner, assets);
  }

  function _mintShare(address to, uint256 amount) internal {
    totalShareSupply += amount;
    _mint(to, 0, amount, "");
  }

  function _burnShare(address from, uint256 amount) internal {
    totalShareSupply -= amount;
    _burn(from, 0, amount);
  }

  function _mintReceipt(address to, uint256 id, uint256 amount, bytes memory) internal {
    require(id > 0, "id #0 is reserved for shares");
    _mint(to, id, amount, "");
  }

  function _burnReceipt(address from, uint256 id, uint256 amount) internal {
    require(id > 0, "id #0 is reserved for shares");
    _burn(from, id, amount);
  }

  /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
  //////////////////////////////////////////////////////////////*/

  function totalAssets() public view virtual returns (uint256);

  function convertToShares(uint256 assets) public view virtual returns (uint256) {
    uint256 supply = totalShareSupply; // Saves an extra SLOAD if totalShareSupply is non-zero.

    return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
  }

  function convertToAssets(uint256 shares) public view virtual returns (uint256) {
    uint256 supply = totalShareSupply; // Saves an extra SLOAD if totalShareSupply is non-zero.

    return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
  }

  function previewDeposit(uint256 assets) public view virtual returns (uint256) {
    return convertToShares(assets);
  }

  function previewMint(uint256 shares) public view virtual returns (uint256) {
    uint256 supply = totalShareSupply; // Saves an extra SLOAD if totalShareSupply is non-zero.

    return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
  }

  function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
    uint256 supply = totalShareSupply; // Saves an extra SLOAD if totalShareSupply is non-zero.

    return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
  }

  function previewRedeem(uint256 shares) public view virtual returns (uint256) {
    return convertToAssets(shares);
  }

  /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
  //////////////////////////////////////////////////////////////*/

  function maxDeposit(address) public view virtual returns (uint256) {
    return type(uint256).max;
  }

  function maxMint(address) public view virtual returns (uint256) {
    return type(uint256).max;
  }

  function maxWithdraw(address owner) public view virtual returns (uint256) {
    return convertToAssets(balanceOf[owner][0]);
  }

  function maxRedeem(address owner) public view virtual returns (uint256) {
    return balanceOf[owner][0];
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
  //////////////////////////////////////////////////////////////*/

  function beforeWithdraw(uint256 assets, uint256 shares) internal virtual {}

  function afterDeposit(uint256 assets, uint256 shares) internal virtual {}
}
