//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "./UniswapV2Library.sol";
import "./Platform.sol";

contract MarketplaceMVPV3 is Initializable,ReentrancyGuardUpgradeable {
    using AddressUpgradeable for address payable;

    enum ListingStatus {
        Active,
        Sold,
        Cancelled
    }

    enum OfferStatus {
        Active,
        Accepted,
        Denied,
        Canceled
    }

    enum StakeStatus {
        Quoted,
        Staking,
        FinishedRentForNFT,
        FinishedRentForCollateral,
        Cancelled
    }
    
    struct OfferForNotListedToken {
        OfferStatus status;
        address to;
        address from;
        uint256 collectionId;
        uint256 tokenId;
        uint256 offerPrice;
        uint256 offerId;
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
        uint256 value;
    }

    struct StakingOffer {
        uint256 collateral;
        uint256 premium;
        uint256 stakingOfferId;
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

     event stopRentalEvent(
        uint256 stakingId
    );

    event ListingOffer(uint256 listingId, address buyer, uint256 amount);

    event ListingOfferCompleted(uint256 listingId, address buyer);

    event OfferForNotListed(OfferStatus status, uint256 offerId,uint256 tokenId, uint256 collectionId, uint256 amount,address actor);

    event StakingOffered(
        uint256 stakingId,
        address taker,
        uint256 collateral,
        uint256 premium,
        uint256 stakingOfferId
    );

    event StakingOfferAccepted(uint256 stakingId, address taker);

    event Rental(uint256 rentalId, address taker, address maker, uint256 startRentalUTC);

    event CancelBid(uint256 listingId, address seller);

    event CancelStaking(uint256 stakingId);

    event FinishRentalForNFT(uint256 rentalId);
    
    event FinishRentalForCollateral(uint256 rentalId);
    
    uint256 public _listingsLastIndex;
    mapping(uint256 => Listing) public _listings;

    uint256 public _stakingsLastIndex;

    mapping(uint256 => Staking) public _stakings;
    mapping(uint256 => StakingExtension) public _stakingsExtension;

    mapping(uint256 => mapping(address => uint256)) _listingOffers;
    mapping(uint256 => mapping(address => StakingOffer)) _stakingOffers;


    // NFT address => NFT id => listing Id
    mapping(address => mapping(uint256 => OptionalUint)) public nftListingIds;

    // NFT address => NFT id => staking Id  
    mapping(address => mapping(uint256 => OptionalUint)) public nftStakingIds;

    uint256 constant premiumPeriod = 7 days;
    uint256 constant premiumFeePercentage = 20;
    uint256 constant bidFeePercent = 2;
    uint256 constant minUndasBalanceForCashback = 10**18;

    uint256 constant tokensDistributionDuration = 5 * 6 weeks; // 6 months with some extra time;
    uint256 constant tokensDistributionFrequency = 1 weeks;

    uint256 constant cashbackPercent = 30;
    uint256 constant discountForTokenFeePercent = 50;

    address public platform ;
    address public undasToken;

    uint256 public  tokensDistributionAmount;
    uint256 public  maxCollateralEligibleForTokens;
    uint256 public  tokensDistributionEnd;
    mapping(address => bool) public NFTsEligibleForTokenDistribution; // protection against DOS
    address public  NFTTokenDistributionWhiteLister; // whitelisting smart contract

    address public  factory;
    address public  wETH;

    uint256 public _offerLastIndex;
    mapping(uint256 => OfferForNotListedToken) public _offersForNotListedTokens;
    uint256 public _stakingOfferIndex;
     function initialize(address _platform,
        address _token,
        address _NFTTokenDistributionWhiteLister,
        uint256 _tokensDistributionAmount,
        uint256 _maxCollateralEligibleForTokens,
        address _factory,
        address _wETH) public initializer{
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
        require(msg.sender == NFTTokenDistributionWhiteLister, "1");

        NFTsEligibleForTokenDistribution[nft] = whitelist;
    }

    function bid(
        address tokenContract,
        uint256 tokenId,
        uint256 priceWei,
        bool isTokenFee
    ) private {
        uint256 expectedValue = (priceWei * bidFeePercent) / 100;
        require(
            IERC721Upgradeable(tokenContract).isApprovedForAll(
                address(msg.sender),
                address(this)
            ),
            "2"
        );
        
        require(
            IERC721Upgradeable(tokenContract).ownerOf(tokenId) == msg.sender,
            "3"
        );
        require(
            isTokenFee || msg.value >= expectedValue,//changed to '>=' because in case bidAndStake we need to send x2 fee cuz it will run payable(platform).transfer(feeValue) 2 times
            "4"
        );
        require(
            !nftListingIds[tokenContract][tokenId].valueExists,
            "5"
        );

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

        nftListingIds[tokenContract][tokenId] = OptionalUint(
            true,
            _listingsLastIndex
        );

        (uint256 a, uint256 cashback) = _takeFeeValue(100, isTokenFee, expectedValue); // warning: if bid is canceled, return cashback intended for buys
        _listings[_listingsLastIndex].cashback = cashback;
        _listings[_listingsLastIndex].isTokenFee = isTokenFee;

        _listingsLastIndex += 1;
      
    }

    function listingOffer(uint256 listingId) external payable nonReentrant {
        Listing storage listing = _listings[listingId];

        require(msg.sender != listing.seller, "6");
        require(isBuyable(listingId), "7");

        _listingOffers[listingId][msg.sender] += msg.value;

        uint256 totalOfferValue = _listingOffers[listingId][msg.sender];

        require(totalOfferValue < listing.price, "8");

        emit ListingOffer(listingId, msg.sender, totalOfferValue);
    }

    function offerForNotListedToken(uint256 collectionId, uint256 tokenId, address tokenContract)payable public  {
        IERC721Upgradeable token = IERC721Upgradeable(tokenContract);
        address tokenOwner = token.ownerOf(tokenId);
        
        require(tokenOwner != msg.sender, "9");

        _offersForNotListedTokens[_offerLastIndex] = OfferForNotListedToken(
            OfferStatus.Active,
            tokenOwner,
            msg.sender,
            collectionId,
            tokenId,
            msg.value,
            _offerLastIndex
        );

        emit OfferForNotListed(OfferStatus.Active, _offerLastIndex,tokenId,collectionId,msg.value,msg.sender);

        _offerLastIndex += 1;
        
   }

   function acceptOfferForNotListedToken(uint256 offerId, address tokenContract) public  {
        IERC721Upgradeable token = IERC721Upgradeable(tokenContract);
        OfferForNotListedToken memory offer = _offersForNotListedTokens[offerId];
    
        require(offer.status == OfferStatus.Active,"10");
        require(offer.to == msg.sender, "11");

        offer.status = OfferStatus.Accepted;
        payable(offer.to).transfer(offer.offerPrice);
        //we need to call approve at front-end

        token.safeTransferFrom(msg.sender, offer.from, offer.tokenId);
        
        emit OfferForNotListed(OfferStatus.Accepted, offer.offerId, offer.tokenId, offer.collectionId, offer.offerPrice,msg.sender);
   }

     function denyOfferForNotListedToken(uint256 offerId) public  {
        OfferForNotListedToken memory offer = _offersForNotListedTokens[offerId];
    
        require(offer.status == OfferStatus.Active,"12");
        require(offer.to == msg.sender, "13");
        payable(offer.from).transfer(offer.offerPrice);
        offer.status = OfferStatus.Denied;
        //we need to call approve at front-end
        
        emit OfferForNotListed(OfferStatus.Denied, offer.offerId, offer.tokenId, offer.collectionId, offer.offerPrice,msg.sender);
   }
   
    function cancelOfferForNotListedToken(uint256 offerId) public  {
        OfferForNotListedToken memory offer = _offersForNotListedTokens[offerId];
    
        require(offer.status == OfferStatus.Active,"14");
        require(offer.from == msg.sender,"15");

        payable(offer.from).transfer(offer.offerPrice);
        offer.status = OfferStatus.Canceled;
        //we need to call approve at front-end
        
        emit OfferForNotListed(OfferStatus.Canceled, offer.offerId, offer.tokenId, offer.collectionId, offer.offerPrice,msg.sender);
        
   }
   

    function buyTokenInternal(
        uint256 listingId,
        uint256 price,
        uint256 value,
        address buyer
    ) private nonReentrant {
        
        IERC721Upgradeable token = IERC721Upgradeable(listing.token);

        require(buyer != listing.seller, "16");
        require(value == price, "17");
        require(isBuyable(listingId), "18");

        listing.status = ListingStatus.Sold;

        token.safeTransferFrom(listing.seller, buyer, listing.tokenId);
        payable(listing.seller).transfer(price);
        
        nftListingIds[listing.token][listing.tokenId] = OptionalUint(
            false,
            listingId
        );

        giveCashback(listing.seller, buyer, listing.cashback,listing.isTokenFee);
    
        emit Sale(listingId, buyer, listing.token, listing.tokenId, price);
    }

    function buyToken(uint256 listingId) external payable {
        Listing storage listing = _listings[listingId];
        buyTokenInternal(listingId, listing.price, msg.value, msg.sender);
    }

    function acceptListingOffer(uint256 listingId, address taker) external {
        Listing memory listing = _listings[listingId];
        require(msg.sender == listing.seller, "19");

        uint256 offerValue = _listingOffers[listingId][taker];
        _listingOffers[listingId][taker] = 0;
        buyTokenInternal(listingId, offerValue, offerValue, taker);
        
         nftListingIds[listing.token][listing.tokenId] = OptionalUint(
            false,
            listingId
        );

        emit ListingOfferCompleted(listingId, taker);
    }

    function cancel(uint256 listingId) public nonReentrant {
        Listing storage listing = _listings[listingId];

        require(msg.sender == listing.seller, "20");
        require(
            listing.status == ListingStatus.Active,
            "21"
        );

        listing.status = ListingStatus.Cancelled;
        nftListingIds[listing.token][listing.tokenId] = OptionalUint(
            false,
            listingId
        );
        emit CancelBid(listingId, listing.seller);
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
        IERC721Upgradeable token = IERC721Upgradeable(listing.token);

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
        uint256 deadlineUTC,//580000 week for ex I want to give my nft for rent for 580000 seconds
        bool isTokenFee                     
    ) private {                             
        uint256 feeValue = (bidFeePercent * collateralWei) / 100;

        require(
            IERC721Upgradeable(tokenContract).isApprovedForAll(
                address(msg.sender),
                address(this)
            ),
            "22"
        );

        require(
            IERC721Upgradeable(tokenContract).ownerOf(tokenId) == msg.sender,
            "23"
        );

        require(isTokenFee || msg.value >= feeValue, "24"); // TODO: Test
        require(
            !nftStakingIds[tokenContract][tokenId].valueExists,
            "25"
        );

        Staking memory stakingQuote = Staking(
            StakeStatus.Quoted,
            msg.sender,
            address(0),
            collateralWei,
            premiumWei,
            0,
            block.timestamp,
            0,
            0,
            deadlineUTC,//!block.timestamp
            tokenContract,
            tokenId
        );

        StakingExtension memory stakingQuoteExtension = StakingExtension(
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
            deadlineUTC//timeForRent
        );

        nftStakingIds[tokenContract][tokenId] = OptionalUint(
            true,
            _stakingsLastIndex
        );

        (uint256 a, uint256 cashback) = _takeFeeValueDistribution(isTokenFee, feeValue);
        _stakingsExtension[_stakingsLastIndex].cashback = cashback;
        _listings[_listingsLastIndex].isTokenFee = isTokenFee;

        _stakingsLastIndex += 1;
    }

    function stakingOffer(
        uint256 stakingId,
        uint256 _collateral,
        uint256 _premium
    ) public payable nonReentrant {
        Staking memory staking = _stakings[stakingId];
        require(staking.maker != msg.sender, "25");
        // require(msg.value == _collateral + _premium + (_premium * premiumFeePercentage / 100), "not enough value"); // _collateral+_premium+_fee //refactored
        require(isEnoughValueWasSend(msg.value, _collateral, _premium, premiumFeePercentage),"26");
        require(_collateral > 0 && _premium > 0, "27");
        require(canRentNFT(stakingId), "28");

        StakingOffer memory offer = _stakingOffers[stakingId][msg.sender];
        payable(msg.sender).transfer(offer.premium * premiumFeePercentage / 100);

        offer.collateral = _collateral;
        offer.premium = _premium;
        offer.stakingOfferId = _stakingOfferIndex;
        require(
            offer.collateral < staking.collateral ||
                offer.premium < staking.premium,
            "29"
        );
        //dasdasd
        _stakingOffers[stakingId][msg.sender] = offer;
        
        

        emit StakingOffered(
            stakingId,
            msg.sender,
            offer.collateral,
            offer.premium,
            _stakingOfferIndex
        );
        _stakingOfferIndex +=1;
    }

    function isEnoughValueWasSend(uint messageValue, uint256 collateral, uint256 premium , uint256 _premiumFeePercentage)internal view returns(bool){ 

        if (messageValue == collateral + premium + (premium * _premiumFeePercentage / 100)){
            return true;
        } 
        else {
            return false;
        }
    }

    function acceptStakingOffer(
        uint256 stakingId,
        address taker,
        bool isTokenFee
    ) public {
        Staking memory staking = _stakings[stakingId];
        require(msg.sender == staking.maker, "30");

        StakingOffer memory offer = _stakingOffers[stakingId][taker];
        _stakingOffers[stakingId][taker] = StakingOffer(0, 0,offer.stakingOfferId);
        rentNFTInternal(
            stakingId,
            offer.collateral,
            offer.premium,
            taker,
            isTokenFee
        );
        
        nftStakingIds[staking.token][staking.tokenId] = OptionalUint(
            false,
            stakingId
        );

        emit StakingOfferAccepted(stakingId, taker);
    }

    function removeStakingOffer(uint256 stakingId) public nonReentrant {
        StakingOffer memory offer = _stakingOffers[stakingId][msg.sender];
        _stakingOffers[stakingId][msg.sender] = StakingOffer(0, 0, offer.stakingOfferId);

        payable(msg.sender).transfer(offer.collateral + offer.premium + (offer.premium * premiumFeePercentage / 100));
        emit StakingOffered(stakingId, msg.sender, 0, 0, offer.stakingOfferId);
    }

    function cancelListingOffer(uint256 listingId) external nonReentrant {
        uint256 offerValue = _listingOffers[listingId][msg.sender];
        _listingOffers[listingId][msg.sender] = 0;
        payable(msg.sender).transfer(offerValue);
        emit ListingOffer(listingId, msg.sender, 0);
    }

    function getStaking(uint256 stakingId)
        public
        view
        returns (Staking memory)
    {
        return _stakings[stakingId];
    }

    function stopStaking(uint256 stakingIndex) public nonReentrant {
        require(
            IERC721Upgradeable(_stakings[stakingIndex].token).isApprovedForAll(
                address(msg.sender),
                address(this)
            ),
            "31"
        );

        require(
            _stakings[stakingIndex].status == StakeStatus.Quoted,
            "32"
        );

        require(
            IERC721Upgradeable(_stakings[stakingIndex].token).ownerOf(
                _stakings[stakingIndex].tokenId
            ) == msg.sender,
            "33"
        );
        Staking memory staking = _stakings[stakingIndex];

        _stakings[stakingIndex].status = StakeStatus.Cancelled;

        nftStakingIds[staking.token][staking.tokenId] = OptionalUint(
                    false,
                    stakingIndex
                );

        emit CancelStaking(stakingIndex);
        
    }

    function canRentNFT(uint256 stakingId) public view returns (bool) {
        Staking storage staking = _stakings[stakingId];

        return
            IERC721Upgradeable(staking.token).isApprovedForAll(
                address(staking.maker),
                address(this)
            ) &&
            IERC721Upgradeable(_stakings[stakingId].token).ownerOf(
                _stakings[stakingId].tokenId
            ) ==
            _stakings[stakingId].maker &&
            staking.status == StakeStatus.Quoted;
    }

    function rentNFT(uint256 stakingId, bool isTokenFee) public payable {
        Staking memory staking = _stakings[stakingId];
       
        // require(msg.value == staking.collateral + staking.premium + (staking.premium * premiumFeePercentage / 100), "!value"); // refactored
        require(isEnoughValueWasSend(msg.value, staking.collateral, staking.premium, premiumFeePercentage), "34");
        require(msg.sender != staking.maker, "35");
        
        rentNFTInternal(
            stakingId,
            staking.collateral,
            staking.premium,
            msg.sender,
            isTokenFee
        );
    }

    function rentNFTInternal(
        uint256 stakingId,
        uint256 collateral,
        uint256 premium,
        address taker,
        bool isTokenFee
    ) private nonReentrant {
        Staking memory staking = _stakings[stakingId];
        StakingExtension memory stakingExt = _stakingsExtension[stakingId];
        require(taker != staking.maker, "36");
        require(
            IERC721Upgradeable(staking.token).isApprovedForAll(
                address(staking.maker),
                address(this)
            ),
            "37"
        );

        require(staking.status == StakeStatus.Quoted, "38");

        staking.startRentalUTC = block.timestamp;//(blocktimestamp + 580000) - 1312312322
        staking.taker = taker;
        staking.status = StakeStatus.Staking;
        staking.paymentsAmount = 1;//!
        staking.premium = premium;
        staking.collateral = collateral;

        _stakings[stakingId] = staking;

        IERC721Upgradeable(staking.token).safeTransferFrom(
            staking.maker,
            staking.taker,
            staking.tokenId
        );

        nftStakingIds[staking.token][staking.tokenId] = OptionalUint(
            false,
            stakingId
        );

        // give the cashback for creating the staking
        // Platform(platform).addCashback(staking.maker, staking.taker, stakingExt.cashback, stakingExt.isTokenFee); //refactored
        giveCashback(staking.maker, staking.taker, stakingExt.cashback, stakingExt.isTokenFee);
        // distribute the premium
        (uint256 etherFeeTaken, uint256 cashback) = _takeFeeValueDistribution(isTokenFee, premiumFeePercentage * premium / 100);

        // send only premium, not msg.value, cause msg.value can be different.
        payable(staking.maker).transfer(premium);
        // payable(platform).transfer(msg.value - cashback);//transfering all tokens to platform
        // give the cashback from the premium
        giveCashback(staking.maker , staking.taker , cashback , isTokenFee);

        emit Rental(stakingId, taker , staking.maker,staking.startRentalUTC);

    }

    function giveCashback(address maker, address taker,uint256 cashback ,bool isTokenFee)internal {
        if (isTokenFee)
        {
            Platform(payable(platform)).addCashback(maker, taker, cashback, isTokenFee);
        }
        else
        {
            Platform(payable(platform)).addCashback{value:cashback*2}(maker, taker, cashback, isTokenFee);
        }
    }

    function payPremium(uint256 stakingId, bool isToken)
        public
        payable
        nonReentrant
    {
        Staking storage staking = _stakings[stakingId];

        uint256 totalFee = (staking.premium * premiumFeePercentage / 100);

        require(staking.status == StakeStatus.Staking, "39");
        require(msg.value == (isToken ? staking.premium : staking.premium + totalFee), "40");
        require(block.timestamp < staking.deadline, "41");//

        uint256 maxPayments = (staking.deadline - staking.startRentalUTC) / premiumPeriod;//max payments == 0

        if ( (staking.deadline - staking.startRentalUTC) % premiumPeriod > 0 ) // if a piece remains
        {
            maxPayments++; // incremeting
        }


        //staking.paymentsAmount=1 maxPaymenrts = 1
        require(staking.paymentsAmount + 1 <= maxPayments, "42");//max paymetns too big number

        staking.paymentsAmount++;

        // distribute the premium

        (uint256 etherFeeTaken, uint256 cashback) = _takeFeeValueDistribution(isToken, totalFee);
        payable(staking.maker).transfer(staking.premium);

        // give the cashback from the premium
        giveCashback(staking.maker, staking.taker, cashback, isToken); // check ether for cashback.
    }

    function paymentsDue(uint256 stakingId)
        public
        view
        returns (int256 amountDue)
    { // TODO test: how many payments remaining upd:r
        Staking memory staking = _stakings[stakingId];

        require(staking.status == StakeStatus.Staking, "43");
        
        uint256 timestampLimitedToDeadline = block.timestamp < staking.deadline
            ? block.timestamp
            : staking.deadline;

        uint256 requiredPayments = (timestampLimitedToDeadline -
            staking.startRentalUTC) / premiumPeriod;

        if (
            (timestampLimitedToDeadline - staking.startRentalUTC) %
                premiumPeriod >
            0
        ) {
            requiredPayments++;
        }

        // negative output means that payments in advance have been made
        return int256(requiredPayments) - int256(staking.paymentsAmount);
    }

    function dateOfNextPayment(uint256 stakingId)
        public
        view
        returns (uint256 date)
    { // THOROUGH TEST
        Staking memory staking = _stakings[stakingId];

        return
            staking.startRentalUTC + (premiumPeriod * staking.paymentsAmount);
    }

    function isCollateralClaimable(uint256 stakingId)
        public
        view
        returns (bool status)
    {
        Staking memory staking = _stakings[stakingId];

        int256 _paymentsDue = paymentsDue(stakingId);

        // collateral is claimable if payments have not been made in time or if the renting is over already;
        return _paymentsDue > 0 || staking.deadline <= block.timestamp;
    }

    // require that premium was not paid, and if so, give the previous owner of NFT (maker) the collateral.
    function claimCollateral(uint256 stakingId) public nonReentrant {
        Staking storage staking = _stakings[stakingId];
        require(staking.status == StakeStatus.Staking, "44");
        require(staking.maker == msg.sender, "45");
        require(
            isCollateralClaimable(stakingId),
            "46"
        );

        staking.status = StakeStatus.FinishedRentForCollateral;
        payable(staking.maker).transfer(staking.collateral);
        delete _stakings[stakingId];
    }

    function claimTokensRent(uint256 id) public {
        Staking storage staking = _stakings[id];
        uint256 eligibleClaims = claimTokensGeneral(
            staking.startStakingUTC,
            staking.tokenPaymentsAmount,
            staking.maker,
            staking.token
        );

        staking.tokenPaymentsAmount += eligibleClaims;
    }

    function claimTokensListing(uint256 id) public {
        Listing storage listing = _listings[id];

        uint256 eligibleClaims = claimTokensGeneral(
            listing.startListingUTC,
            listing.tokenPaymentsAmount,
            listing.seller,
            listing.token
        );

        listing.tokenPaymentsAmount += eligibleClaims;
    }

    // general function for claiming tokens for staking/listing
    // returns how many token claims have been made in this function
    function claimTokensGeneral(
        uint256 stakingStartUTC,
        uint256 tokenPaymentsAmount,
        address maker,
        address token
    ) private nonReentrant returns (uint256) {
        require(block.timestamp < tokensDistributionEnd, "47");
        require(NFTsEligibleForTokenDistribution[token], "48");

        uint256 eligibleClaims = (block.timestamp - stakingStartUTC) /
            tokensDistributionFrequency -
            tokenPaymentsAmount;
        uint256 tokensToIssue = tokensDistributionAmount * eligibleClaims;

        IERC20Upgradeable(undasToken).transfer(maker, tokensToIssue); // it is assumed that tokens have been allocated for this contract earlier.

        return eligibleClaims;
    }

    function stopRental(uint256 stakingId) public nonReentrant {
        Staking storage staking = _stakings[stakingId];
        require(staking.status == StakeStatus.Staking, "49");
        require(staking.taker == msg.sender, "50");

        uint256 requiredPayments = (block.timestamp - staking.startRentalUTC) /
            premiumPeriod;
        require(
            staking.paymentsAmount >= requiredPayments,
            "51"
        );

        // change status
        staking.status = StakeStatus.FinishedRentForNFT;
        
        // return nft
        IERC721Upgradeable(staking.token).safeTransferFrom(
            staking.taker,
            staking.maker,
            staking.tokenId
        );
        
        // return collateral
        payable(staking.taker).transfer(staking.collateral);
        delete _stakings[stakingId];

        emit stopRentalEvent(stakingId);
    }

    // TODO: Fix different msg.value expectations 
    function bidAndStake(
        address tokenContract,
        uint256 tokenId,
        uint256 collateralWei,
        uint256 premiumWei,
        uint256 deadlineUTC,
        uint256 priceWei,
        bool isTokenFee
    ) external payable nonReentrant {
        require(msg.value != 0, "52");
 
        quoteForStaking(
            tokenContract,
            tokenId,
            collateralWei,
            premiumWei,
            deadlineUTC,
            isTokenFee
        );
        bid(tokenContract, tokenId, priceWei, isTokenFee);
    }

    function bidExternal(
        address tokenContract,
        uint256 tokenId,
        uint256 priceWei,
        bool isTokenFee
    ) external payable nonReentrant {
        bid(tokenContract, tokenId, priceWei, isTokenFee);
    }

    function quoteForStakingExternal(
        address tokenContract,
        uint256 tokenId,
        uint256 collateralWei,
        uint256 premiumWei,
        uint256 deadlineUTC,
        bool isTokenFee
    ) external payable nonReentrant {
        quoteForStaking(
            tokenContract,
            tokenId,
            collateralWei,
            premiumWei,
            deadlineUTC,
            isTokenFee
        );
    }   
    
    // returns how much ether and cashback was taken (ether, cashback)
    function _takeFeeValue(
        uint256 percent,
        bool isToken,
        uint256 value
    ) internal returns (uint256 etherFeeTaken, uint256 cashbackAmount) {
       
        uint256 feeValue = (value * percent) / 100;

        return _takeFeeValueDistribution(isToken, feeValue);
    }
    // Calculates and transfers fee to the Platform contract, calculates cashback but does not transfer it.
    function _takeFeeValueDistribution (bool isToken, uint256 feeValue) internal returns (uint256 etherFeeTaken, uint256 cashbackAmount) { 
        uint256 _cashbackPercent;

        if (IERC20Upgradeable(undasToken).balanceOf(msg.sender) < minUndasBalanceForCashback) { // abuse possible
            _cashbackPercent = 0;
        }
        else
        {
            _cashbackPercent = cashbackPercent;
        }

        if (isToken) {
            address[] memory path = new address[](2);
            path[0] = wETH;
            path[1] = undasToken;

            uint256 tokenFee = UniswapV2Library.getAmountsOut(factory, feeValue, path)[1] * discountForTokenFeePercent / 100; // 50% saving
           
            IERC20Upgradeable(undasToken).transferFrom(msg.sender, platform, tokenFee);

            cashbackAmount = (tokenFee * _cashbackPercent) / 100;
            return (0, cashbackAmount);
        } else {
            
            cashbackAmount = (feeValue * _cashbackPercent) / 100;
            payable(platform).sendValue(feeValue);

            return (feeValue, cashbackAmount);
        }
    }

   receive() external payable{
    
   }

}