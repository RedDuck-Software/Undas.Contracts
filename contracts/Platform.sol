//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";

// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Staking is Context {
    struct StakingInfo {
        uint256 reservedRewards;
        uint256 stakePeriod;
    }

    mapping(address => StakingInfo[]) public userStaking;
    
    uint256 public totalStaked;

    address public immutable token;

    constructor(address _token) {
        token = _token;
    }

    // /// @notice returns array of staking periods in months
    // function getStakePeriods() public pure returns(uint256[] memory) { 
    //     return [2,3,4];
    // }

    // /// @notice returns array of staking periods in months with precition 
    // function getStakePeriodsMultipliers() public pure returns(uint256[] memory) { 
    //     return [2,3,4];
    // }

    // function calculateUserRewards(address user) public view returns(uint256) {
    //     return 0;
    // }

    function stake(uint256 stakePeriod) external {
        // uint256 rewards = calculateUserRewards(_msgSender());

        // require(rewards == 0, "!rewards");

        // userStaking[_msgSender()].push(
        //     StakingInfo({reservedRewards: _msgSender(), stakePeriod: })
        // );
    }

    function claimFor(address staker, uint256 amount) external {}
}

contract Platform is Staking {
    constructor(address token) Staking(token) {}
}
