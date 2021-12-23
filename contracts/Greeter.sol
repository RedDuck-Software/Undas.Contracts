//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721.sol";

contract Marketplace {    
    enum ListingStatus {
        Active,
        Sold,
        Cancelled
    }

    enum StakeStatus {
        Quoted,
        Staking,
        FinishedRentForNFT,
        FinishedRentForCollateral
    }

    struct Listing {
        ListingStatus status;
        address seller;
        uint price;
        address token;
        uint tokenId;
    }

    struct Staking {
        StakeStatus status;
        address maker;
        address taker;
        uint collateral;
        uint premium;
        uint startRentalUTC;
        uint lastPaymentUTC;
        uint paymentsAmount;
        uint deadline;
        address token;
        uint tokenId;
    }

    event Listed(
		uint listingId,
		address seller,
		address token,
		uint tokenId,
		uint price
	);

    event QuotedForStaking(
		uint stakingId,
		address maker,
		address token,
		uint tokenId,
		uint collateral,
        uint premium,
        uint deadline
	);    
    
	event Sale(
		uint listingId,
		address buyer,
		address token,
		uint tokenId,
		uint price
	);

    event Rental(
        uint rentalId,
        address taker
    );

	event CancelBid(
		uint listingId,
		address seller
	);

    event FinishRentalForNFT(uint rentalId);
    event FinishRentalForCollateral(uint rentalId);

    uint _bidFee;

    uint _listingsLength;
    mapping (uint => Listing) _listings;

    uint _stakingsLength;
    mapping (uint => Staking) _stakings;

    uint constant premiumPeriod = 7 days;

    function bid(address tokenContract, uint tokenId, uint priceWei) external payable {
        require(IERC721(tokenContract).isApprovedForAll(address(msg.sender), address(this)), "allowance not set");
        require(msg.value >= _bidFee, "bidFee");

        Listing memory listing = Listing(
            ListingStatus.Active,
            msg.sender,
            priceWei,
            tokenContract,
            tokenId
        );

        _listings[_listingsLength] = listing; 

        _listingsLength++;

        emit Listed(
			_listingsLength - 1,
			msg.sender,
			tokenContract,
			tokenId,
			priceWei
		);
    }

    function getListing(uint listingId) public view returns (Listing memory) {
		return _listings[listingId];
	}

    function isBuyable(uint listingId) public view returns (bool) {
        Listing storage listing = _listings[listingId];
        IERC721 token = IERC721(listing.token);
        
        return
            token.ownerOf(listingId) == listing.seller
            && listing.status == ListingStatus.Active;
    }

	function buyToken(uint listingId) external payable {
		Listing storage listing = _listings[listingId];
        IERC721 token = IERC721(listing.token);

		require(msg.sender != listing.seller, "Seller cannot be buyer");
		require(listing.status == ListingStatus.Active, "Listing is not active");
		require(msg.value >= listing.price, "Insufficient payment");
        require(token.ownerOf(listingId) == listing.seller, "Seller is not owner");

		listing.status = ListingStatus.Sold;

		token.transferFrom(listing.seller, msg.sender, listing.tokenId);
		payable(listing.seller).transfer(listing.price);

		emit Sale(
			listingId,
			msg.sender,
			listing.token,
			listing.tokenId,
			listing.price
		);
	}

	function cancel(uint listingId) public {
		Listing storage listing = _listings[listingId];

		require(msg.sender == listing.seller, "Only seller can cancel listing");
		require(listing.status == ListingStatus.Active, "Listing is not active");

		listing.status = ListingStatus.Cancelled;
	
        payable(listing.seller).transfer(_bidFee);

		emit CancelBid(listingId, listing.seller);
	}

    // innovation from Only1NFT - renting & staking
    // is coded below
    function quoteForStaking(address tokenContract, uint tokenId, uint collateralWei, uint premiumWei, uint deadlineUTC) public payable
    {
        require(IERC721(tokenContract).isApprovedForAll(address(msg.sender), address(this)), "allowance not set");
        require(msg.value >= _bidFee, "bidFee");
        
        Staking memory stakingQuote = Staking(
            StakeStatus.Quoted,
            msg.sender,
            address(0),
            collateralWei,
            premiumWei,
            0, 0, 0,
            deadlineUTC,
            tokenContract,
            tokenId
        );

        _stakings[_stakingsLength] = stakingQuote; 

        _stakingsLength++;

        emit QuotedForStaking(
			_stakingsLength - 1,
			msg.sender,
			tokenContract,
			tokenId,
			collateralWei,
            premiumWei,
            deadlineUTC
		);
    }

    function rentNFT(uint stakingId) public payable
    {
        Staking memory staking = _stakings[stakingId];

        require(IERC721(staking.token).isApprovedForAll(address(msg.sender), address(this)), "allowance not set");
        require(msg.value >= staking.collateral + staking.premium, "collateral");

        staking.lastPaymentUTC = block.timestamp;
        staking.startRentalUTC = block.timestamp;
        staking.taker = msg.sender;
        staking.status = StakeStatus.Staking;
        staking.paymentsAmount = 1;

        // todo immediatelly send premium and fees to corresponding accounts

        // todo think: what if it doesn't have a revert in case of no allowance and does nothing?
        IERC721(staking.token).transferFrom(staking.maker, staking.taker, staking.tokenId);
    }

    // todo - distribute the premium among everyone
    function payPremium(uint stakingId) public payable
    {
        Staking memory staking = _stakings[stakingId];

        require(msg.value >= staking.premium);

        staking.lastPaymentUTC = block.timestamp;

        staking.paymentsAmount++;
    }

    // require that premium was not paid, and if so, give the previous owner of NFT (maker) the collateral.
    function claimCollateral(uint stakingId) public
    {
        Staking memory staking = _stakings[stakingId];
        require(staking.status == StakeStatus.Quoted, "non-active staking");
        require(staking.maker == msg.sender, "not maker");

        uint requiredPayments = (block.timestamp - staking.startRentalUTC) / premiumPeriod;
        require(staking.paymentsAmount < requiredPayments, "premiums have been paid");

        payable(staking.maker).transfer(staking.collateral);
        staking.status = StakeStatus.FinishedRentForCollateral;
    }

    function stopRental(uint stakingId) public
    {
        Staking memory staking = _stakings[stakingId];
        require(staking.status == StakeStatus.Quoted, "non-active staking");
        require(staking.taker == msg.sender, "not taker");

        uint requiredPayments = (block.timestamp - staking.startRentalUTC) / premiumPeriod;
        require(staking.paymentsAmount >= requiredPayments, "premiums have not been paid");

        // return nft
        IERC721(staking.token).transferFrom(staking.taker, staking.maker, staking.tokenId);
        staking.status = StakeStatus.FinishedRentForNFT;
    }
}