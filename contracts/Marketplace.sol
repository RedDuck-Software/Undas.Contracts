//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

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
        uint256 lastPaymentUTC;
        uint256 paymentsAmount;
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

    uint256 _bidFee;

    uint256 _listingsLength;
    mapping(uint256 => Listing) _listings;

    uint256 _stakingsLength;
    mapping(uint256 => Staking) _stakings;

    uint256 constant premiumPeriod = 7 days;

    function bid(
        address tokenContract,
        uint256 tokenId,
        uint256 priceWei
    ) external payable {
        require(
            IERC721(tokenContract).isApprovedForAll(
                address(msg.sender),
                address(this)
            ),
            "allowance not set"
        );
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

    function getListing(uint256 listingId)
        public
        view
        returns (Listing memory)
    {
        return _listings[listingId];
    }

    function isBuyable(uint256 listingId) public view returns (bool) {
        Listing storage listing = _listings[listingId];
        IERC721 token = IERC721(listing.token);

        return
            token.ownerOf(listingId) == listing.seller &&
            token.isApprovedForAll(listing.seller, address(this)) &&
            listing.status == ListingStatus.Active;
    }

    function buyToken(uint256 listingId) external payable {
        Listing storage listing = _listings[listingId];
        IERC721 token = IERC721(listing.token);

        require(msg.sender != listing.seller, "Seller cannot be buyer");
        require(msg.value >= listing.price, "Insufficient payment");
        require(isBuyable(listingId), "not buyable");

        // todo: move the fee (bidFee) to our DAO account

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

    // todo: add a public function without "only seller" restriction that will
    // 1. check if NFT is not on the owners acconut
    // 2. if so, do everything as in cancel() (remove the listing, replace last item with current)
    // 3. 50% of bidFee is sent to the account of person who called the function, 50% to our DAO
    // we send 50% of bidfee to the msg.sender to incentivize people to find and remove inactive listings
    function cancel(uint256 listingId) public {
        Listing storage listing = _listings[listingId];

        require(msg.sender == listing.seller, "Only seller can cancel listing");
        require(
            listing.status == ListingStatus.Active,
            "Listing is not active"
        );

        listing.status = ListingStatus.Cancelled;

        payable(listing.seller).transfer(_bidFee);

        emit CancelBid(listingId, listing.seller);
    }

    // innovation from Only1NFT - renting & staking
    // is coded below
    function quoteForStaking(
        address tokenContract,
        uint256 tokenId,
        uint256 collateralWei,
        uint256 premiumWei,
        uint256 deadlineUTC
    ) public payable {
        require(
            IERC721(tokenContract).isApprovedForAll(
                address(msg.sender),
                address(this)
            ),
            "allowance not set"
        );
        require(msg.value >= _bidFee, "bidFee");

        Staking memory stakingQuote = Staking(
            StakeStatus.Quoted,
            msg.sender,
            address(0),
            collateralWei,
            premiumWei,
            0,
            0,
            0,
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

    function rentNFT(uint256 stakingId) public payable {
        Staking memory staking = _stakings[stakingId];

        require(
            IERC721(staking.token).isApprovedForAll(
                address(msg.sender),
                address(this)
            ),
            "allowance not set"
        );
        require(
            msg.value >= staking.collateral + staking.premium,
            "collateral"
        );

        staking.lastPaymentUTC = block.timestamp;
        staking.startRentalUTC = block.timestamp;
        staking.taker = msg.sender;
        staking.status = StakeStatus.Staking;
        staking.paymentsAmount = 1;

        // todo immediatelly send premium and fees to corresponding accounts

        // todo think: what if it doesn't have a revert in case of no allowance and does nothing?
        IERC721(staking.token).transferFrom(
            staking.maker,
            staking.taker,
            staking.tokenId
        );
    }

    // todo - distribute the premium among everyone
    function payPremium(uint256 stakingId) public payable {
        Staking memory staking = _stakings[stakingId];

        require(msg.value >= staking.premium);

        staking.lastPaymentUTC = block.timestamp;

        staking.paymentsAmount++;
    }

    function isCollateralClaimable(uint256 stakingId) public view {
        Staking memory staking = _stakings[stakingId];
        require(staking.status == StakeStatus.Quoted, "non-active staking");
        require(staking.maker == msg.sender, "not maker");

        uint256 requiredPayments = (block.timestamp - staking.startRentalUTC) /
            premiumPeriod;
        require(
            staking.paymentsAmount < requiredPayments ||
                staking.deadline > block.timestamp,
            "premiums have been paid and deadline is yet to be reached"
        );
    }

    // require that premium was not paid, and if so, give the previous owner of NFT (maker) the collateral.
    function claimCollateral(uint256 stakingId) public {
        Staking memory staking = _stakings[stakingId];
        isCollateralClaimable(stakingId);

        payable(staking.maker).transfer(staking.collateral);
        staking.status = StakeStatus.FinishedRentForCollateral;
    }

    function stopRental(uint256 stakingId) public {
        Staking memory staking = _stakings[stakingId];
        require(staking.status == StakeStatus.Quoted, "non-active staking");
        require(staking.taker == msg.sender, "not taker");

        uint256 requiredPayments = (block.timestamp - staking.startRentalUTC) /
            premiumPeriod;
        require(
            staking.paymentsAmount >= requiredPayments,
            "premiums have not been paid"
        );

        // return nft
        IERC721(staking.token).transferFrom(
            staking.taker,
            staking.maker,
            staking.tokenId
        );
        // return collateral
        payable(staking.taker).transfer(staking.collateral);
        // change status
        staking.status = StakeStatus.FinishedRentForNFT;
    }
}
