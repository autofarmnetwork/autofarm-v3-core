// SPDX-License-Identifier: MIT
//              _         __                 __      ______
//             | |       / _|                \ \    / /___ \
//   __ _ _   _| |_ ___ | |_ __ _ _ __ _ __ __\ \  / /  __) |
//  / _` | | | | __/ _ \|  _/ _` | '__| '_ ` _ \ \/ /  |__ <
// | (_| | |_| | || (_) | || (_| | |  | | | | | \  /   ___) |
//  \__,_|\__,_|\__\___/|_| \__,_|_|  |_| |_| |_|\/   |____/

pragma solidity ^0.8.13;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth} from "solmate/auth/authorities/RolesAuthority.sol";
import {VaultRewarderTime} from "./VaultRewarderTime.sol";

abstract contract RewardableVault is Auth, ERC4626 {
  using SafeTransferLib for ERC20;

  event RewarderFailure(bytes err);

  uint256 public constant GRACE_PERIOD = 2 weeks;
  uint256 public constant MAX_CONCURRENT_REWARDERS = 2;

  address public rewarder;

  function setRewarder(
    address rewardToken,
    uint256 emissionRate,
    uint256 startTime,
    uint256 endTime
  ) public requiresAuth returns (address _rewarder) {
    if (rewarder != address(0)) {
      removeRewarder();
    }

    VaultRewarderTime _rewarder = new VaultRewarderTime(
      address(this),
      rewardToken,
      emissionRate,
      startTime,
      endTime
    );
    rewarder = address(_rewarder);
    uint256 totalRewards = (endTime - startTime) * emissionRate;
    ERC20(rewardToken).safeTransferFrom(
      msg.sender, address(_rewarder), totalRewards
    );
  }

  function removeRewarder() public requiresAuth {
    address _rewarder = rewarder; // gas saving
    require(_rewarder != address(0), "Rewarder does not exist");

    rewarder = address(0);
  }

  function _mint(address to, uint256 amount) internal override {
    super._mint(to, amount);

    address _rewarder = rewarder; // gas saving

    if (_rewarder != address(0)) {
      uint256 balance = balanceOf[to];
      try VaultRewarderTime(_rewarder).updateUserRewards(
        to, balance - amount, balance, totalSupply - amount
      ) {} catch (bytes memory err) {
        rewarder = address(0);
        emit RewarderFailure(err);
      }
    }
  }

  function _burn(address from, uint256 amount) internal override {
    super._burn(from, amount);

    address _rewarder = rewarder; // gas saving

    if (_rewarder != address(0)) {
      uint256 balance = balanceOf[from];
      try VaultRewarderTime(_rewarder).updateUserRewards(
        from, balance + amount, balance, totalSupply + amount
      ) {} catch (bytes memory err) {
        rewarder = address(0);
        emit RewarderFailure(err);
      }
    }
  }

  function transfer(address to, uint256 amount)
    public
    override
    returns (bool success)
  {
    success = super.transfer(to, amount);

    address _rewarder = rewarder; // gas saving

    if (success && _rewarder != address(0)) {
      uint256 balanceSender = balanceOf[msg.sender];
      uint256 balanceReceiver = balanceOf[to];
      try VaultRewarderTime(_rewarder).updateUsersRewards(
        [msg.sender, to],
        [balanceSender + amount, balanceReceiver - amount],
        [balanceSender, balanceReceiver],
        totalSupply
      ) {} catch (bytes memory err) {
        rewarder = address(0);
        emit RewarderFailure(err);
      }
    }
  }

  function transferFrom(address from, address to, uint256 amount)
    public
    override
    returns (bool success)
  {
    success = super.transferFrom(from, to, amount);

    address _rewarder = rewarder; // gas saving

    if (success && _rewarder != address(0)) {
      uint256 balanceSender = balanceOf[from];
      uint256 balanceReceiver = balanceOf[to];
      try VaultRewarderTime(_rewarder).updateUsersRewards(
        [from, to],
        [balanceSender + amount, balanceReceiver - amount],
        [balanceSender, balanceReceiver],
        totalSupply
      ) {} catch (bytes memory err) {
        rewarder = address(0);
        emit RewarderFailure(err);
      }
    }
  }
}
