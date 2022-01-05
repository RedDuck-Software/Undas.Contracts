//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

contract Staking is Context, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct StakingInfo {
        uint256 staked;
        uint256 reservedRewards;
        uint256 stakePeriod;
        uint256 stakedAt;
    }

    mapping(address => StakingInfo[]) public userStaking;

    uint256 public totalStaked;
    uint256 public totalReserved;

    address public immutable token;

    event Staked(
        address indexed staker,
        uint256 stakedAmount,
        uint256 stakeIndex,
        uint256 timestamp
    );

    event Claimed(
        address indexed staker,
        uint256 claimedRewards,
        uint256 timestamp
    );

    constructor(address _token) {
        token = _token;
    }

    /// @notice returns array of staking periods in months
    function getStakePeriods() public pure returns (uint8[3] memory) {
        return [2, 3, 4];
    }

    /// @notice returns array of staking periods in months with precition
    function getStakePeriodsMultipliers()
        public
        pure
        returns (uint8[3] memory)
    {
        // x1.20
        return [120, 130, 140];
    }

    function calculateUserRewards(uint256 stakeAmount, uint256 stakePeriod)
        public
        view
        returns (uint256)
    {
        uint256 multiplier = getStakePeriodsMultipliers()[stakePeriod];

        uint256 rewardsWithoutMultiplier = (((address(this).balance -
            totalReserved) *
            ((totalStaked * 100) / (stakeAmount + totalStaked))) / 100);

        return rewardsWithoutMultiplier * multiplier;
    }

    function stakeWithPermit(
        uint256 amount,
        uint8 stakePeriod,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        IERC20Permit(token).permit(
            _msgSender(),
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );
        _stake(amount, stakePeriod);
    }

    function stake(uint256 amount, uint8 stakePeriod) external nonReentrant {
        _stake(amount, stakePeriod);
    }

    function _stake(uint256 amount, uint8 stakePeriod) internal {
        require(stakePeriod < getStakePeriods().length, "!stakePeriod");
        require(amount != 0, "!amount");

        IERC20(token).safeTransferFrom(_msgSender(), address(this), amount);

        uint256 rewards = calculateUserRewards(amount, stakePeriod);

        require(rewards == 0, "!rewards");
        require(rewards <= address(this).balance, "!balance");

        userStaking[_msgSender()].push(
            StakingInfo({
                staked: amount,
                reservedRewards: rewards,
                stakePeriod: uint256(getStakePeriods()[stakePeriod]) * 1 days,
                stakedAt: block.timestamp
            })
        );

        totalStaked += amount;
        totalReserved += rewards;

        emit Staked(
            _msgSender(),
            amount,
            userStaking[_msgSender()].length - 1,
            block.timestamp
        );
    }

    function claimFor(address staker, uint8 stakeIndex) external nonReentrant {
        require(stakeIndex < userStaking[staker].length, "!stakeIndex");
        StakingInfo memory staking = userStaking[staker][stakeIndex];

        require(
            block.timestamp > staking.stakedAt + staking.stakePeriod * 1 days,
            "!period"
        );

        userStaking[staker][stakeIndex] = userStaking[staker][
            userStaking[staker].length - 1
        ];

        userStaking[staker].pop();

        totalStaked -= staking.reservedRewards;
        totalReserved -= staking.staked;

        payable(staker).transfer(staking.reservedRewards);
        emit Claimed(staker, staking.reservedRewards, block.timestamp);
    }
}

contract Platform is Staking {
    constructor(address token) Staking(token) {}
}
