pragma solidity >=0.8.13;

interface IPancakeswapFarm {
  // Info of each user.
  struct UserInfo {
    uint256 amount; // How many LP tokens the user has provided.
    uint256 rewardDebt; // Reward debt. See explanation below.
      //
      // We do some fancy math here. Basically, any point in time, the amount of CAKEs
      // entitled to a user but is pending to be distributed is:
      //
      //   pending reward = (user.amount * pool.accCakePerShare) - user.rewardDebt
      //
      // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
      //   1. The pool's `accCakePerShare` (and `lastRewardBlock`) gets updated.
      //   2. User receives the pending reward sent to his/her address.
      //   3. User's `amount` gets updated.
      //   4. User's `rewardDebt` gets updated.
  }

  // Deposit LP tokens to MasterChef for CAKE allocation.
  function deposit(uint256 _pid, uint256 _amount) external;

  // Withdraw LP tokens from MasterChef.
  function withdraw(uint256 _pid, uint256 _amount) external;
  function emergencyWithdraw(uint256 _pid) external;

  // Stake CAKE tokens to MasterChef
  function enterStaking(uint256 _amount) external;

  // Withdraw CAKE tokens from STAKING.
  function leaveStaking(uint256 _amount) external;

  function userInfo(uint256 pid, address userAddress)
    external
    view
    returns (UserInfo memory);
  function pendingCake(uint256 _pid, address _user)
    external
    view
    returns (uint256);
}