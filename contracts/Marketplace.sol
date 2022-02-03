//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

contract Marketplace is ReentrancyGuard {
    enum ListingStatus {
        Active,
        Sold,
        Cancelled
    }

    enum StakeStatus {
        Quoted,
        Staking,
        FinishedRentForNFT,
        FinishedRentForCollateral,
        Cancelled
    }

    struct Listing {
        ListingStatus status;
        address seller;
        uint256 price;
        address token;
        uint256 tokenId;
    }

    struct Staking {
        StakeStatus status;
        address maker;
        address taker;
        uint256 collateral;
        uint256 premium;
        uint256 startRentalUTC;
        uint256 startStakingUTC;
        uint256 paymentsAmount;
        uint256 tokenPaymentsAmount;
        uint256 deadline;
        address token;
        uint256 tokenId;
    }

    event Listed(
        uint256 listingId,
        address seller,
        address token,
        uint256 tokenId,
        uint256 price
    );

    event QuotedForStaking(
        uint256 stakingId,
        address maker,
        address token,
        uint256 tokenId,
        uint256 collateral,
        uint256 premium,
        uint256 deadline
    );

    event Sale(
        uint256 listingId,
        address buyer,
        address token,
        uint256 tokenId,
        uint256 price
    );

    event Rental(uint256 rentalId, address taker);

    event CancelBid(uint256 listingId, address seller);

    event FinishRentalForNFT(uint256 rentalId);
    event FinishRentalForCollateral(uint256 rentalId);

    uint256 public _listingsLastIndex;
    mapping(uint256 => Listing) public _listings;

    uint256 public _stakingsLastIndex;
    mapping(uint256 => Staking) public  _stakings;

    // NFT address => NFT id => listing Id 
    mapping (address => mapping (uint => uint)) public nftListingIds;

    // NFT address => NFT id => staking Id 
    mapping (address => mapping (uint => uint)) public nftStakingIds;

    uint256 constant premiumPeriod = 7 days;
    uint256 constant premiumFeePercentage = 20;
    uint256 constant bidFee = 0.1 ether;

    uint256 constant tokensDistributionDuration = 5*6 weeks; // 6 months with some extra time;
    uint256 constant tokensDistributionFrequency = 1 weeks;

    address public immutable platform;
    address public immutable undasToken;

    uint256 public immutable tokensDistributionAmount;
    uint256 public immutable maxCollateralEligibleForTokens;
    uint256 public immutable tokensDistributionEnd;
    mapping (address => bool) public NFTsEligibleForTokenDistribution; // protection against DOS
    address public immutable NFTTokenDistributionWhiteLister; // whitelisting smart contract

    constructor(address _platform, address _token, address _NFTTokenDistributionWhiteLister, uint256 _tokensDistributionAmount, uint256 _maxCollateralEligibleForTokens) {
        platform = _platform;
        undasToken = _token;
        NFTTokenDistributionWhiteLister = _NFTTokenDistributionWhiteLister;
        tokensDistributionAmount = _tokensDistributionAmount;
        maxCollateralEligibleForTokens = _maxCollateralEligibleForTokens;
        tokensDistributionEnd = block.timestamp + tokensDistributionDuration;
    }

    function whiteListNFTToggle(address nft, bool whitelist) external {
        require(msg.sender == NFTTokenDistributionWhiteLister, "fuck off .|.");

        NFTsEligibleForTokenDistribution[nft] = whitelist;
    }

    function bid(
        address tokenContract,
        uint256 tokenId,
        uint256 priceWei
    ) external payable nonReentrant {
        require(
            IERC721(tokenContract).isApprovedForAll(
                address(msg.sender),
                address(this)
            ),
            "!allowance"
        );

        require(
            IERC721(tokenContract).ownerOf(tokenId) == msg.sender, "token ownership");

        require(msg.value == bidFee, "!bidFee");
        _takeFee(bidFee);

        _listings[_listingsLastIndex] = Listing(
            ListingStatus.Active,
            msg.sender,
            priceWei,
            tokenContract,
            tokenId
        );

        emit Listed(
            _listingsLastIndex,
            msg.sender,
            tokenContract,
            tokenId,
            priceWei
        );

        nftListingIds[tokenContract][tokenId] = _listingsLastIndex;

        _listingsLastIndex += 1;
    }

    function getListing(uint256 listingId)
        public
        view
        returns (Listing memory)
    {
        return _listings[listingId];
    }

    function isBuyable(uint256 listingId) public view returns (bool) {
        Listing memory listing = _listings[listingId];
        IERC721 token = IERC721(listing.token);

        return
            token.ownerOf(listing.tokenId) == listing.seller &&
            token.isApprovedForAll(listing.seller, address(this)) &&
            listing.status == ListingStatus.Active;
    }

    function buyToken(uint256 listingId) external payable nonReentrant {
        Listing storage listing = _listings[listingId];
        IERC721 token = IERC721(listing.token);

        require(msg.sender != listing.seller, "Seller cannot be buyer");
        require(msg.value == listing.price, "Insufficient payment");
        require(isBuyable(listingId), "not buyable");

        listing.status = ListingStatus.Sold;

        token.safeTransferFrom(listing.seller, msg.sender, listing.tokenId);
        payable(listing.seller).transfer(listing.price);

        emit Sale(
            listingId,
            msg.sender,
            listing.token,
            listing.tokenId,
            listing.price
        );
    }

    function cancel(uint256 listingId) public nonReentrant {
        Listing storage listing = _listings[listingId];

        require(msg.sender == listing.seller, "Only seller can cancel listing");
        require(
            listing.status == ListingStatus.Active,
            "Listing is not active"
        );

        listing.status = ListingStatus.Cancelled;

        emit CancelBid(listingId, listing.seller);
    }

    // innovation from Only1NFT team - renting & staking
    // is coded below
    function quoteForStaking(
        address tokenContract,
        uint256 tokenId,
        uint256 collateralWei,
        uint256 premiumWei,
        uint256 deadlineUTC
    ) public payable nonReentrant {
        //bool isRounded = (deadlineUTC - block.timestamp) % premiumPeriod == 0;
        //deadlineUTC = isRounded ? deadlineUTC : block.timestamp + (((deadlineUTC - block.timestamp) / premiumPeriod + 1) * premiumPeriod);

        require(
            IERC721(tokenContract).isApprovedForAll(
                address(msg.sender),
                address(this)
            ),
            "allowance not set"
        );

        require(
            IERC721(tokenContract).ownerOf(tokenId) == msg.sender, 
            "token ownership");

        require(msg.value == bidFee, "!bidFee");

        Staking memory stakingQuote = Staking(
            StakeStatus.Quoted,
            msg.sender,
            address(0),
            collateralWei,
            premiumWei,
            0,
            block.timestamp, // stakingTimestamp
            0,
            0,
            deadlineUTC,
            tokenContract,
            tokenId
        );

        _stakings[_stakingsLastIndex] = stakingQuote;

        emit QuotedForStaking(
            _stakingsLastIndex,
            msg.sender,
            tokenContract,
            tokenId,
            collateralWei,
            premiumWei,
            deadlineUTC
        );

        nftStakingIds[tokenContract][tokenId] = _stakingsLastIndex;

        _stakingsLastIndex += 1;
    }
	
	function getStaking(uint256 stakingId)
        public
        view
        returns (Staking memory)
    {
        return _stakings[stakingId];
    }

// 1-------2-------3-------4-------5
// startRentalUTC: 1643862701; startStakingUTC: 1643862162;; paymentsAmount 1; 604800 premiumPeriod; deadline 1646281362;
    function stopStaking(uint stakingIndex) public nonReentrant {
        require(
            IERC721(_stakings[stakingIndex].token).isApprovedForAll(
                address(msg.sender),
                address(this)
            ),
            "allowance not set"
        );

        require(_stakings[stakingIndex].status == StakeStatus.Quoted, "should be status quoted");

        require(
            IERC721(_stakings[stakingIndex].token).ownerOf(_stakings[stakingIndex].tokenId) == msg.sender, 
            "token ownership");

        _stakings[stakingIndex].status = StakeStatus.Cancelled;
        _takeFee(bidFee);
    }

    function canRentNFT(uint256 stakingId) public view returns (bool) {
        Staking storage staking = _stakings[stakingId];

        return IERC721(staking.token).isApprovedForAll(
                address(staking.maker),
                address(this)
            ) && IERC721(_stakings[stakingId].token).ownerOf(_stakings[stakingId].tokenId) == _stakings[stakingId].maker 
            && staking.status == StakeStatus.Quoted;
    }
    // 0-------1-------2-------3-------4
    function rentNFT(uint256 stakingId) public payable nonReentrant {
        Staking storage staking = _stakings[stakingId];

		require(msg.sender != staking.maker, "Maker cannot be taker");
        require(
            IERC721(staking.token).isApprovedForAll(
                address(staking.maker),
                address(this)
            ),
            "!allowance"
        );
        require(
            msg.value == staking.collateral + staking.premium,
            "!collateral"
        );

        require(staking.status == StakeStatus.Quoted, "status");

        staking.startRentalUTC = block.timestamp;
        staking.taker = msg.sender;
        staking.status = StakeStatus.Staking;
        staking.paymentsAmount = 1;

        IERC721(staking.token).safeTransferFrom(
            staking.maker,
            staking.taker,
            staking.tokenId
        );

        payable(staking.maker).transfer(bidFee); // return bidFee back

        // distribute the premium
        uint fee = staking.premium / 100 * premiumFeePercentage;
        uint makerCut = staking.premium - fee;
        _takeFee(fee);
        payable(staking.maker).transfer(makerCut);
    }

    function payPremium(uint256 stakingId) public payable {
        Staking storage staking = _stakings[stakingId];

        require(staking.status == StakeStatus.Staking, "status != staking");
        require(msg.value == staking.premium, "premium");
        require(block.timestamp < staking.deadline, "deadline reached");
        // 90 - 30 = 60 / 30 = 2; 30-60;60-90;
        // 150 - 30 = 120 / 30 = 4; 3 + 1 <= 4 -> true

        uint256 maxPayments = (staking.deadline - staking.startRentalUTC) / premiumPeriod;
        if ((staking.deadline - staking.startRentalUTC) % premiumPeriod > 0) // if a piece remains
        {
            maxPayments++;
        }
        require (staking.paymentsAmount + 1 <= maxPayments, "too many payments");

        // distribute the premium
        uint fee = msg.value / 100 * premiumFeePercentage;
        uint makerCut = msg.value - fee;
        _takeFee(fee);
        payable(staking.maker).transfer(makerCut);

        staking.paymentsAmount++;
    }

    function paymentsDue(uint256 stakingId) public view returns (int256 amountDue) {
        Staking memory staking = _stakings[stakingId];

        require(staking.status == StakeStatus.Staking, "status");

        uint256 timestampLimitedToDeadline = block.timestamp < staking.deadline ? block.timestamp : staking.deadline;

        uint256 requiredPayments = (timestampLimitedToDeadline - staking.startRentalUTC) / premiumPeriod;

        if ((timestampLimitedToDeadline - staking.startRentalUTC) % premiumPeriod > 0)
        {
            requiredPayments++;
        }

        // negative output means that payments in advance have been made
        return int256(requiredPayments) - int256(staking.paymentsAmount);
    }

    function dateOfNextPayment(uint256 stakingId) public view returns (uint256 date) {
        Staking memory staking = _stakings[stakingId];

        return staking.startRentalUTC + (premiumPeriod * staking.paymentsAmount);
    }

    function isCollateralClaimable(uint256 stakingId) public view returns(bool status) {
        Staking memory staking = _stakings[stakingId];

        int256 _paymentsDue = paymentsDue(stakingId);

        // collateral is claimable if payments have not been made in time or if the renting is over already;
        return _paymentsDue > 0 || staking.deadline <= block.timestamp;
    }

    // require that premium was not paid, and if so, give the previous owner of NFT (maker) the collateral.
    function claimCollateral(uint256 stakingId) public nonReentrant {

        Staking storage staking = _stakings[stakingId];
        require(staking.status == StakeStatus.Staking, "status != staking");
        require(staking.maker == msg.sender, "not maker");
        require (isCollateralClaimable(stakingId), "premiums have been paid and deadline is yet to be reached");

        staking.status = StakeStatus.FinishedRentForCollateral;
        payable(staking.maker).transfer(staking.collateral);
        delete _stakings[stakingId];
    }

    function claimTokens(uint256 stakingId) public nonReentrant {
        require(block.timestamp < tokensDistributionEnd, "ended");

        Staking storage staking = _stakings[stakingId];

        require (NFTsEligibleForTokenDistribution[staking.token], "bad NFT");

        uint256 eligibleClaims = (block.timestamp - staking.startStakingUTC) / tokensDistributionFrequency - staking.tokenPaymentsAmount;
        uint256 tokensToIssue = tokensDistributionAmount * eligibleClaims;

        staking.tokenPaymentsAmount += eligibleClaims;

        IERC20(undasToken).transfer(staking.maker, tokensToIssue); // it is assumed that tokens have been allocated for this contract earlier.
    }

    function stopRental(uint256 stakingId) public nonReentrant {
        Staking storage staking = _stakings[stakingId];
        require(staking.status == StakeStatus.Staking, "non-active staking");
        require(staking.taker == msg.sender, "not taker");

        uint256 requiredPayments = (block.timestamp - staking.startRentalUTC) /
            premiumPeriod;
        require(
            staking.paymentsAmount >= requiredPayments,
            "premiums have not been paid"
        );

        // change status
        staking.status = StakeStatus.FinishedRentForNFT;

        // return nft
        IERC721(staking.token).safeTransferFrom(
            staking.taker,
            staking.maker,
            staking.tokenId
        );
        // return collateral
        payable(staking.taker).transfer(staking.collateral);
        delete _stakings[stakingId];
    }

    function _takeFee(uint256 _amount) internal {
        payable(platform).transfer(_amount);
    }
}