// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract UndasMVP is ERC721, ERC721Enumerable {

    address public owner;

    enum Category{ ARTWORK, SPORTS, PHOTOGRAPHY, GAMEFI, CELEBRITY, RWANFT,EXCPLICIT,OTHER}

    event createdCollection(Category, string collectionName, uint256 collectionId, string information, string logoImgUrl,string featuredImgUrl,string bannerImgUrl, address owner);

    event collectionTokenMint(address to, uint256 tokenId, string name, string url, string description, uint256 collectionId);
    
    event verify(uint256 collectionId);

    struct Collection {
        string name;
        address owner;
        Category category;
        bool isVerified; 
        string logoImgUrl;
        string featuredImgUrl;
        string bannerImgUrl;
    }

    struct Metadata {
        string description;
        string name;
        string url;
        uint256 collectionId;
    }

    using Counters for Counters.Counter;
    using Strings for uint256;
    
    Counters.Counter private _tokenIdCounter;
    Counters.Counter private _collectionsIdCounter;
    
    mapping (uint256 => Collection) public collections;
    mapping (uint256 => Metadata) public tokenMetadata;

    bool public isOthersCollectionCreated;

    constructor() ERC721("Undas", "Undas") {
        owner = msg.sender;
    }

    function createCollection(
        string memory _collectionName, 
        string memory _logoImgUrl, 
        string memory _featuredImgUrl, 
        string memory _bannerImgUrl, 
        string memory _information,
        Category _category
    ) public {

            if(_category == Category.OTHER) {
                require(isOthersCollectionCreated == false,"only1 others collecton is available");
                isOthersCollectionCreated = true;
            }

            uint256 collectionId = _collectionsIdCounter.current();
            _collectionsIdCounter.increment();

            Collection storage collection = collections[collectionId]; 

            collection.name = _collectionName;
            collection.owner = msg.sender;
            collection.category = _category;

            emit createdCollection(_category, _collectionName, collectionId, _information, _logoImgUrl,_featuredImgUrl,_bannerImgUrl, msg.sender);
        }   


    function safeMintGeneral(
        address to,
        string calldata description,
        string calldata name,
        string calldata url,
        uint256 collectionId
    ) public {
        Collection storage collection = collections[collectionId]; 
        
        if(collection.category != Category.OTHER){
            require(collection.owner == msg.sender,"!collection.owner");
        }

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        mintGeneral(to, tokenId, description, name, url, collectionId);

    }

    function mintGeneral(
        address to,
        uint256 tokenId,
        string calldata description,
        string calldata name,
        string calldata url,
        uint256 collectionId

    ) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);
        _mint(to, tokenId);

        tokenMetadata[tokenId] = Metadata(description, name, url,collectionId);

        emit collectionTokenMint(to,tokenId,name,url,description,collectionId);

        emit Transfer(address(0), to, tokenId);
    }

    function verifyCollection(uint256 collectionId)public isOwner {
        Collection storage collection = collections[collectionId]; 
        collection.isVerified = true;
        
        emit verify(collectionId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }


    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (bytes(tokenMetadata[tokenId].url).length == 0) {
            string memory baseURI = _baseURI();
            return
                bytes(baseURI).length > 0
                    ? string(abi.encodePacked(baseURI, tokenId.toString()))
                    : "";
        } else {
            return tokenMetadata[tokenId].url;
        }
    }


    modifier isOwner(){

        require(msg.sender == owner,"not an owner");
        _;  
    }       

}
