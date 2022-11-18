// SPDX-License-Identifier: MIT
//              _         __                 __      ______
//             | |       / _|                \ \    / /___ \
//   __ _ _   _| |_ ___ | |_ __ _ _ __ _ __ __\ \  / /  __) |
//  / _` | | | | __/ _ \|  _/ _` | '__| '_ ` _ \ \/ /  |__ <
// | (_| | |_| | || (_) | || (_| | |  | | | | | \  /   ___) |
//  \__,_|\__,_|\__\___/|_| \__,_|_|  |_| |_| |_|\/   |____/

pragma solidity ^0.8.13;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth} from "solmate/auth/authorities/RolesAuthority.sol";
import {VaultRewarderTime} from "./VaultRewarderTime.sol";

error VaultRemovalNotAllowed();

/*
 * RewardableVault
 * Use for boosting a vault with multiple reward tokens.
 * Each reward token boosting is handled by a separate rewarder contract.
 */ 
abstract contract RewardableVault is Auth, ERC20 {
  using SafeTransferLib for ERC20;

  event RewarderFailure(bytes err);

  uint256 public constant GRACE_PERIOD = 6 weeks;
  // The total number of active and past rewarders that will
  // remain synced with the vault.
  // The limit should be set based on the gas price of the network.
  // Each extra rewarder costs N
  uint256 public constant MAX_CONCURRENT_REWARDERS = 3;

  address[MAX_CONCURRENT_REWARDERS] public rewarders;

  function setRewarder(
    address rewardToken,
    uint256 emissionRate,
    uint256 startTime,
    uint256 endTime
  ) public requiresAuth returns (address _rewarderAddr) {
    address[MAX_CONCURRENT_REWARDERS] memory _rewarders = rewarders; // gas saving

    // Find empty slot or one past grace period
    uint256 i;
    for (; i < MAX_CONCURRENT_REWARDERS;) {
      if (_rewarders[i] == address(0)) {
        break;
      }
      if (block.timestamp > VaultRewarderTime(_rewarders[i]).endTime() + GRACE_PERIOD) {
        removeRewarder(i);
        break;
      }
      unchecked { i++; }
    }

    VaultRewarderTime _rewarder = new VaultRewarderTime(
      address(this),
      i,
      rewardToken,
      emissionRate,
      startTime,
      endTime,
      msg.sender
    );

    _rewarderAddr = address(_rewarder);

    uint256 totalRewards = (endTime - startTime) * emissionRate;
    ERC20(rewardToken).safeTransferFrom(
      msg.sender, _rewarderAddr, totalRewards
    );

    rewarders[i] = _rewarderAddr;
  }

  function removeRewarder(uint256 i) public requiresAuth {
    address _rewarder = rewarders[i]; // gas saving
    require(_rewarder != address(0), "Rewarder does not exist");

    if (block.timestamp <= VaultRewarderTime(_rewarder).endTime() + GRACE_PERIOD) {
      revert VaultRemovalNotAllowed();
    }

    rewarders[i] = address(0);
  }

  function _mint(address to, uint256 amount) internal override virtual {
    super._mint(to, amount);

    uint256 _balance = balanceOf[to];
    uint256 _totalSupply = totalSupply;

    address[MAX_CONCURRENT_REWARDERS] memory _rewarders = rewarders; // gas saving

    for (uint i; i < MAX_CONCURRENT_REWARDERS;) {
      address _rewarder = _rewarders[i];

      if (_rewarder != address(0)) {
        try VaultRewarderTime(_rewarder).updateUserRewards(
          to, _balance - amount, _balance, _totalSupply - amount
        ) {} catch (bytes memory err) {
          rewarders[i] = address(0);
          emit RewarderFailure(err);
        }
      }

      unchecked { i++; }
    }
  }

  function _burn(address from, uint256 amount) internal override virtual {
    super._burn(from, amount);

    uint256 _balance = balanceOf[from];
    uint256 _totalSupply = totalSupply;

    address[MAX_CONCURRENT_REWARDERS] memory _rewarders = rewarders; // gas saving

    for (uint i; i < MAX_CONCURRENT_REWARDERS;) {
      address _rewarder = _rewarders[i];

      if (_rewarder != address(0)) {
        try VaultRewarderTime(_rewarder).updateUserRewards(
          from, _balance + amount, _balance, _totalSupply + amount
        ) {} catch (bytes memory err) {
          rewarders[i] = address(0);
          emit RewarderFailure(err);
        }
      }

      unchecked { i++; }
    }
  }

  function transfer(address to, uint256 amount)
    public
    override
    virtual
    returns (bool success)
  {
    success = super.transfer(to, amount);

    if (success) {
      uint256 _balanceSender = balanceOf[msg.sender];
      uint256 _balanceReceiver = balanceOf[to];
      uint256 _totalSupply = totalSupply;

      address[MAX_CONCURRENT_REWARDERS] memory _rewarders = rewarders; // gas saving

      for (uint i; i < MAX_CONCURRENT_REWARDERS;) {
        address _rewarder = _rewarders[i];

        if (_rewarder != address(0)) {
          try VaultRewarderTime(_rewarder).updateUsersRewards(
            [msg.sender, to],
            [_balanceSender + amount, _balanceReceiver - amount],
            [_balanceSender, _balanceReceiver],
            _totalSupply
          ) {} catch (bytes memory err) {
            rewarders[i] = address(0);
            emit RewarderFailure(err);
          }
        }

        unchecked { i++; }
      }
    }
  }

  function transferFrom(address from, address to, uint256 amount)
    public
    override
    virtual
    returns (bool success)
  {
    success = super.transferFrom(from, to, amount);

    if (success) {
      uint256 _balanceSender = balanceOf[from];
      uint256 _balanceReceiver = balanceOf[to];
      uint256 _totalSupply = totalSupply;

      address[MAX_CONCURRENT_REWARDERS] memory _rewarders = rewarders; // gas saving

      for (uint i; i < MAX_CONCURRENT_REWARDERS;) {
        address _rewarder = _rewarders[i];

        if (_rewarder != address(0)) {
          try VaultRewarderTime(_rewarder).updateUsersRewards(
            [from, to],
            [_balanceSender + amount, _balanceReceiver - amount],
            [_balanceSender, _balanceReceiver],
            _totalSupply
          ) {} catch (bytes memory err) {
            rewarders[i] = address(0);
            emit RewarderFailure(err);
          }
        }

        unchecked { i++; }
      }
    }
  }
}
