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

    mapping (address => StakingInfo[]) public userStaking;
    mapping (address => uint256) public etherCashback;
    mapping (address => uint256) public tokenCashback;

    uint256 public lockedEtherCashBack;
    uint256 public lockedTokenCashback;

    uint256 public totalStaked;
    uint256 public totalReserved;

    address public immutable token;
    address public immutable owner;
    address public marketplace;

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

    constructor(address _owner, address _token) {
        token = _token;
        owner = _owner;
    }

    function setMarketplaceAddress(address _marketplace) public only(owner) {
        marketplace = _marketplace;
    }

    function receiveWithLockedCashback(uint256 percentCashback) external payable only(marketplace) {
        lockedEtherCashBack += msg.value * percentCashback / 100;
    }

    function lockTokenCashback(uint256 amount) external only(marketplace) {
        lockedTokenCashback += amount;
    }

    function addCashback(address cashbackee1, address cashbackee2, uint256 amount, bool isTokenFee) external only(marketplace) {
        if (isTokenFee)
        {
            tokenCashback[cashbackee1] += amount;
            tokenCashback[cashbackee2] += amount;
        }
        else
        {
            etherCashback[cashbackee1] += amount;
            etherCashback[cashbackee2] += amount;
        }
    }

    function calculateUserRewards(uint256 stakeAmount, uint256 stakePeriod)
        public
        view
        returns (uint256)
    {
        uint256 rewardsWithoutMultiplier = (((address(this).balance -
            totalReserved) *
            ((totalStaked * 100) / (stakeAmount + totalStaked))) / 100);

        return rewardsWithoutMultiplier;
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

    modifier only(address who) {
        require(msg.sender == who, "only address fail");
        _;
    }
}

contract Platform is Staking {
    constructor(address owner, address token) Staking(owner, token) {}
}
