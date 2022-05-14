//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./UniswapV2Library.sol";
import "./Platform.sol";
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
        uint256 startListingUTC;
        uint256 tokenPaymentsAmount;
        uint256 cashback;
        bool isTokenFee;
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
    struct StakingExtension {
        uint256 cashback;
        bool isTokenFee;
    }
    struct OptionalUint {
        bool valueExists;
        uint value;
    }

    struct StakingOffer {
        uint256 collateral;
        uint256 premium;
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

    event ListingOffer(
        uint256 listingId,
        address buyer,
        uint256 amount
    );

    event ListingOfferCompleted(
        uint256 listingId,
        address buyer
    );
    
    event StakingOffered(
        uint256 stakingId,
        address taker,
        uint256 collateral,
        uint256 premium
    );

    event StakingOfferAccepted(
        uint256 stakingId,
        address taker
    );

    event Rental(uint256 rentalId, address taker);

    event CancelBid(uint256 listingId, address seller);

    event FinishRentalForNFT(uint256 rentalId);
    event FinishRentalForCollateral(uint256 rentalId);

    uint256 public _listingsLastIndex;
    mapping(uint256 => Listing) public _listings;

    uint256 public _stakingsLastIndex;

    mapping(uint256 => Staking) public  _stakings;
    mapping(uint256 => StakingExtension) public _stakingsExtension;

    mapping (uint256 => mapping (address => uint256)) _listingOffers;
    mapping (uint256 => mapping (address => StakingOffer)) _stakingOffers;

    // NFT address => NFT id => listing Id 
    mapping (address => mapping (uint => OptionalUint)) public nftListingIds;

    // NFT address => NFT id => staking Id 
    mapping (address => mapping (uint => OptionalUint)) public nftStakingIds;

    uint256 constant premiumPeriod = 7 days;
    uint256 constant premiumFeePercentage = 20;
    uint256 constant bidFeePercent = 2;
    uint256 constant minUndasBalanceForCashback = 10**18;

    uint256 constant tokensDistributionDuration = 5*6 weeks; // 6 months with some extra time;
    uint256 constant tokensDistributionFrequency = 1 weeks;

    uint256 constant cashbackPercent = 30;

    address public immutable platform;
    address public immutable undasToken;

    uint256 public immutable tokensDistributionAmount;
    uint256 public immutable maxCollateralEligibleForTokens;
    uint256 public immutable tokensDistributionEnd;
    mapping (address => bool) public NFTsEligibleForTokenDistribution; // protection against DOS
    address public immutable NFTTokenDistributionWhiteLister; // whitelisting smart contract

    address public immutable factory;
    address public immutable wETH;

    constructor(address _platform, address _token, address _NFTTokenDistributionWhiteLister, 
                uint256 _tokensDistributionAmount, uint256 _maxCollateralEligibleForTokens, address _factory, address _wETH) {
        platform = _platform;
        undasToken = _token;
        NFTTokenDistributionWhiteLister = _NFTTokenDistributionWhiteLister;
        tokensDistributionAmount = _tokensDistributionAmount;
        maxCollateralEligibleForTokens = _maxCollateralEligibleForTokens;
        tokensDistributionEnd = block.timestamp + tokensDistributionDuration;
        factory = _factory;
        wETH = _wETH;
    }

    function whiteListNFTToggle(address nft, bool whitelist) external {
        require(msg.sender == NFTTokenDistributionWhiteLister, "fuck off .|.");

        NFTsEligibleForTokenDistribution[nft] = whitelist;
    }

    function bid(
        address tokenContract,
        uint256 tokenId,
        uint256 priceWei,
        bool isTokenFee
    ) private {
        require(
            IERC721(tokenContract).isApprovedForAll(
                address(msg.sender),
                address(this)
            ),
            "!allowance"
        );

        require(IERC721(tokenContract).ownerOf(tokenId) == msg.sender, "token ownership");
        require(isTokenFee || msg.value == priceWei * bidFeePercent / 100, "!bidFee");
        require(!nftListingIds[tokenContract][tokenId].valueExists, "already exists listing");

        _listings[_listingsLastIndex] = Listing(
            ListingStatus.Active,
            msg.sender,
            priceWei,
            tokenContract,
            tokenId,
            block.timestamp,
            0, 
            0,
            isTokenFee
        );

        emit Listed(
            _listingsLastIndex,
            msg.sender,
            tokenContract,
            tokenId,
            priceWei
        );

        nftListingIds[tokenContract][tokenId] = OptionalUint(true, _listingsLastIndex);

        (uint256 a, uint256 cashback) = _takeFee(100, isTokenFee);
        _listings[_listingsLastIndex].cashback = cashback;
        _listings[_listingsLastIndex].isTokenFee = isTokenFee;

        _listingsLastIndex += 1;
    }

    function listingOffer(uint256 listingId) external payable nonReentrant { 
        Listing storage listing = _listings[listingId];

        require(msg.sender != listing.seller, "Seller cannot be buyer");
        require(isBuyable(listingId), "not buyable");

        _listingOffers[listingId][msg.sender] += msg.value;

        uint256 totalOfferValue = _listingOffers[listingId][msg.sender];

        require(totalOfferValue < listing.price, "Too high offer");

        emit ListingOffer(listingId, msg.sender, totalOfferValue);
    }

    function buyTokenInternal(uint256 listingId, uint256 price, uint256 value, address buyer) private nonReentrant {
        Listing storage listing = _listings[listingId];
        IERC721 token = IERC721(listing.token);

        require(buyer != listing.seller, "Seller cannot be buyer");
        require(value == price, "Insufficient payment");
        require(isBuyable(listingId), "not buyable");

        listing.status = ListingStatus.Sold;

        token.safeTransferFrom(listing.seller, buyer, listing.tokenId);
        payable(listing.seller).transfer(price);

        // Platform(platform).addCashback(listing.seller, buyer, listing.cashback, listing.isTokenFee);

        emit Sale(
            listingId,
            buyer,
            listing.token,
            listing.tokenId,
            price
        );
    }

    function buyToken(uint256 listingId) external payable {
        Listing storage listing = _listings[listingId];
        buyTokenInternal(listingId, listing.price, msg.value, msg.sender);
    }
    
    function acceptListingOffer(uint256 listingId, address taker) external {
        Listing memory listing = _listings[listingId];
        require(msg.sender == listing.seller, "non-seller");

        uint256 offerValue = _listingOffers[listingId][taker];
        _listingOffers[listingId][taker] = 0;
        buyTokenInternal(listingId, offerValue, offerValue, taker);

        emit ListingOfferCompleted(listingId, taker);
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
    
    function cancelListingOffer(uint256 listingId) external nonReentrant {
        uint256 offerValue = _listingOffers[listingId][msg.sender];
        _listingOffers[listingId][msg.sender] = 0;
        payable(msg.sender).transfer(offerValue);
        emit ListingOffer(listingId, msg.sender, 0);
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

    // innovation from Only1NFT team - renting & staking
    // is coded below
    function quoteForStaking(
        address tokenContract,
        uint256 tokenId,
        uint256 collateralWei,
        uint256 premiumWei,
        uint256 deadlineUTC,
        bool isTokenFee
    ) private {

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

        require(msg.value == bidFeePercent * collateralWei / 100, "!bidFee");
        require(!nftStakingIds[tokenContract][tokenId].valueExists, "already staked");

        Staking memory stakingQuote = Staking(
            StakeStatus.Quoted,
            msg.sender,
            address(0),
            collateralWei,
            premiumWei,
            0, block.timestamp, 0, 0,
            deadlineUTC,
            tokenContract,
            tokenId
        );

        StakingExtension memory stakingQuoteExtension = StakingExtension (
            0, 
            isTokenFee
        );

        _stakings[_stakingsLastIndex] = stakingQuote;
        _stakingsExtension[_stakingsLastIndex] = stakingQuoteExtension;

        emit QuotedForStaking(
            _stakingsLastIndex,
            msg.sender,
            tokenContract,
            tokenId,
            collateralWei,
            premiumWei,
            deadlineUTC
        );

        nftStakingIds[tokenContract][tokenId] = OptionalUint(true, _stakingsLastIndex);

        (uint256 a, uint256 cashback) = _takeFee(100, isTokenFee);
        _stakingsExtension[_stakingsLastIndex].cashback = cashback;
        _listings[_listingsLastIndex].isTokenFee = isTokenFee;

        _stakingsLastIndex += 1;
    }

    function stakingOffer(uint256 stakingId, uint256 _collateral, uint256 _premium) public payable nonReentrant {
        Staking memory staking = _stakings[stakingId];
        require(staking.maker != msg.sender, "only taker can offer");
        require(msg.value == _collateral + _premium, "not enough value");
        require(_collateral > 0 && _premium > 0, "empty offer");
        require(canRentNFT(stakingId), "cannot rent");

        StakingOffer memory offer = _stakingOffers[stakingId][msg.sender];
        offer.collateral += _collateral;
        offer.premium += _premium;

        require(offer.collateral < staking.collateral || offer.premium < staking.premium, "collateral&premium");

        _stakingOffers[stakingId][msg.sender] = offer;

        emit StakingOffered(stakingId, msg.sender, offer.collateral, offer.premium);
    }

    function acceptStakingOffer(uint256 stakingId, address taker, bool isTokenFee) public {
        Staking memory staking = _stakings[stakingId];
        require (msg.sender == staking.maker, "non-maker");

        StakingOffer memory offer = _stakingOffers[stakingId][taker];
        _stakingOffers[stakingId][taker] = StakingOffer(0, 0);
        rentNFTInternal(stakingId, offer.collateral, offer.premium, taker, isTokenFee);

        emit StakingOfferAccepted(stakingId, taker);
    }

    function removeStakingOffer(uint256 stakingId) public nonReentrant {
        StakingOffer memory offer = _stakingOffers[stakingId][msg.sender];
        _stakingOffers[stakingId][msg.sender] = StakingOffer(0, 0);

        payable(msg.sender).transfer(offer.collateral + offer.premium);
        emit StakingOffered(stakingId, msg.sender, 0, 0);
    }

	function getStaking(uint256 stakingId)
        public
        view
        returns (Staking memory)
    {
        return _stakings[stakingId];
    }

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
    }

    function canRentNFT(uint256 stakingId) public view returns (bool) {
        Staking storage staking = _stakings[stakingId];

        return IERC721(staking.token).isApprovedForAll(
                address(staking.maker),
                address(this)
            ) && IERC721(_stakings[stakingId].token).ownerOf(_stakings[stakingId].tokenId) == _stakings[stakingId].maker 
            && staking.status == StakeStatus.Quoted;
    }

    function rentNFT(uint256 stakingId, bool isTokenFee) public payable {
        Staking memory staking = _stakings[stakingId];
        require(msg.value == staking.collateral + staking.premium, "!value");
		require(msg.sender != staking.maker, "Maker cannot be taker");

        rentNFTInternal(stakingId, staking.collateral, staking.premium, msg.sender, isTokenFee);
    }

    function rentNFTInternal(uint256 stakingId, uint256 collateral, uint256 premium, address taker, bool isTokenFee) private nonReentrant {
        Staking memory staking = _stakings[stakingId];
        StakingExtension memory statindExt = _stakingsExtension[stakingId];
		require(taker != staking.maker, "Maker cannot be taker");
        require(
            IERC721(staking.token).isApprovedForAll(
                address(staking.maker),
                address(this)
            ),
            "!allowance"
        );

        require(staking.status == StakeStatus.Quoted, "status");

        staking.startRentalUTC = block.timestamp;
        staking.taker = taker;
        staking.status = StakeStatus.Staking;
        staking.paymentsAmount = 1;
        staking.premium = premium;
        staking.collateral = collateral;

        _stakings[stakingId] = staking;

        IERC721(staking.token).safeTransferFrom(
            staking.maker,
            staking.taker,
            staking.tokenId
        );

        // give the cashback for creating the staking
        // Platform(platform).addCashback(staking.maker, staking.taker,
        //  statindExt.cashback, statindExt.isTokenFee);

        // distribute the premium
        (uint256 etherFeeTaken, uint256 cashback) = _takeFeeValue(premiumFeePercentage, isTokenFee, premium); // premium - override value to not send collateral
        payable(staking.maker).transfer(premium - etherFeeTaken);

        // give the cashback from the premium
        // Platform(platform).addCashback(staking.maker, staking.taker, cashback, isTokenFee);
    }

    function payPremium(uint256 stakingId, bool isToken) public payable nonReentrant {
        Staking storage staking = _stakings[stakingId];

        require(staking.status == StakeStatus.Staking, "status != staking");
        require(msg.value == staking.premium, "premium");
        require(block.timestamp < staking.deadline, "deadline reached");

        uint256 maxPayments = (staking.deadline - staking.startRentalUTC) / premiumPeriod;
        if ((staking.deadline - staking.startRentalUTC) % premiumPeriod > 0) // if a piece remains
        {
            maxPayments++;
        }
        require (staking.paymentsAmount + 1 <= maxPayments, "too many payments");

        staking.paymentsAmount++;

        // distribute the premium

        (uint256 etherFeeTaken, uint256 cashback) = _takeFee(premiumFeePercentage, isToken);
        payable(staking.maker).transfer(msg.value - etherFeeTaken);

        // give the cashback from the premium
        // Platform(platform).addCashback(staking.maker, staking.taker, cashback, isToken);
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

    function claimTokensRent(uint256 id) public {
        Staking storage staking = _stakings[id];
        uint256 eligibleClaims = claimTokensGeneral(staking.startStakingUTC, staking.tokenPaymentsAmount, staking.maker, staking.token);

        staking.tokenPaymentsAmount += eligibleClaims;        
    }

    function claimTokensListing(uint256 id) public {
        Listing storage listing = _listings[id];

        uint256 eligibleClaims = claimTokensGeneral(listing.startListingUTC, listing.tokenPaymentsAmount, listing.seller, listing.token);

        listing.tokenPaymentsAmount += eligibleClaims;
    }

    // general function for claiming tokens for staking/listing 
    // returns how many token claims have been made in this function
    function claimTokensGeneral(uint256 stakingStartUTC, uint256 tokenPaymentsAmount, address maker, address token) private nonReentrant returns (uint256) {
        require(block.timestamp < tokensDistributionEnd, "ended");
        require (NFTsEligibleForTokenDistribution[token], "bad NFT");

        uint256 eligibleClaims = (block.timestamp - stakingStartUTC) / tokensDistributionFrequency - tokenPaymentsAmount;
        uint256 tokensToIssue = tokensDistributionAmount * eligibleClaims;

        IERC20(undasToken).transfer(maker, tokensToIssue); // it is assumed that tokens have been allocated for this contract earlier.

        return eligibleClaims;
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

    function bidAndStake(address tokenContract, uint256 tokenId, uint256 collateralWei, uint256 premiumWei, uint256 deadlineUTC, uint256 priceWei, bool isTokenFee) external payable nonReentrant {
        require (msg.value != 0, "msgvaluezero");
        
        quoteForStaking(tokenContract, tokenId, collateralWei, premiumWei, deadlineUTC, isTokenFee);
        bid(tokenContract, tokenId, priceWei, isTokenFee);
    }

    function bidExternal(
        address tokenContract,
        uint256 tokenId,
        uint256 priceWei,
        bool isTokenFee) external payable nonReentrant
    {
        bid(tokenContract, tokenId, priceWei, isTokenFee);
    }

    function quoteForStakingExternal(
        address tokenContract,
        uint256 tokenId,
        uint256 collateralWei,
        uint256 premiumWei,
        uint256 deadlineUTC, 
        bool isTokenFee) external payable nonReentrant
    {
        quoteForStaking(tokenContract, tokenId, collateralWei, premiumWei, deadlineUTC, isTokenFee);
    }

    function _takeFee(uint256 percent, bool isToken) internal returns (uint256, uint256)
    {
        return _takeFeeValue(percent, isToken, msg.value * percent / 100);
    }

    // returns how much ether and cashback was taken (ether, cashback)
    function _takeFeeValue(uint256 percent, bool isToken, uint256 value) internal returns (uint256, uint256) {
        uint256 _cashbackPercent = cashbackPercent;
        
        if (IERC20(undasToken).balanceOf(msg.sender) < minUndasBalanceForCashback)
        {
            _cashbackPercent = 0;
        }
        
        if (isToken) {
            address[] memory path = new address[](2);
            path[0] = wETH;
            path[1] = undasToken;

            uint256 tokenFee = UniswapV2Library.getAmountsOut(factory, value, path)[1] / 2; // 50% saving
            uint256 cashbackAmount = tokenFee * _cashbackPercent / 100;

            IERC20(undasToken).transferFrom(msg.sender, platform, tokenFee);
            // multiply by two because we want to lock two cashbacks: for taker and for maker
            // Platform(payable(platform)).lockTokenCashback(cashbackAmount * 2);
            
            return (0, cashbackAmount);
        }
        else {
            Platform(payable(platform)).receiveWithLockedCashback{value:value}(_cashbackPercent * 2);
            return (value, value * _cashbackPercent / 100);
        }
    }
}