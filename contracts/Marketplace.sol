//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
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

    uint256 public _listingsLastIndex;
    mapping(uint256 => Listing) public _listings;

    uint256 public _stakingsLastIndex;
    mapping(uint256 => Staking) public  _stakings;

    uint256 constant premiumPeriod = 7 days;
    uint256 constant premiumFeePercentage = 20;
    uint256 constant bidFee = 0.1 ether;

    address public immutable platform;

    constructor(address _platform) {
        platform = _platform;
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
        require(msg.value >= listing.price, "Insufficient payment");
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

        _stakingsLastIndex += 1;
    }

    function stopStaking(uint stakingIndex) public nonReentrant {
        require(
            IERC721(_stakings[stakingIndex].token).isApprovedForAll(
                address(msg.sender),
                address(this)
            ),
            "allowance not set"
        );

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
            ) && IERC721(_stakings[stakingId].token).ownerOf(_stakings[stakingId].tokenId) == _stakings[stakingId].maker;
    }

    function rentNFT(uint256 stakingId) public payable {
        Staking storage staking = _stakings[stakingId];

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

        staking.startRentalUTC = block.timestamp;
        staking.taker = msg.sender;
        staking.status = StakeStatus.Staking;
        staking.paymentsAmount = 1;

        IERC721(staking.token).safeTransferFrom(
            staking.maker,
            staking.taker,
            staking.tokenId
        );

        payable(staking.maker).transfer(bidFee); // return bidFee

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

        // distribute the premium
        uint fee = msg.value / 100 * premiumFeePercentage;
        uint makerCut = msg.value - fee;
        _takeFee(fee);
        payable(staking.maker).transfer(makerCut);

        staking.paymentsAmount++;
    }

    function isCollateralClaimable(uint256 stakingId) public view {
        Staking memory staking = _stakings[stakingId];
        require(staking.status == StakeStatus.Staking, "status != staking");
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
        Staking storage staking = _stakings[stakingId];
        isCollateralClaimable(stakingId);

        staking.status = StakeStatus.FinishedRentForCollateral;
        payable(staking.maker).transfer(staking.collateral);
        delete _stakings[stakingId];
    }

    function stopRental(uint256 stakingId) public nonReentrant {
        Staking storage staking = _stakings[stakingId];
        require(staking.status == StakeStatus.Quoted, "non-active staking");
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