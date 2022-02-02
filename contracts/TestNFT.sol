// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract UndasGeneralNFT is ERC721, ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    struct Metadata
    {
        string description;
        string name;
        string url;
    }

    mapping (uint256 => Metadata) public tokenMetadata;

    constructor() ERC721("UndasGeneral", "UndasGeneral") {}

    function safeMintGeneral(address to, string calldata description, string calldata name, string calldata url) public {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        mintGeneral(to, tokenId, description, name, url);
    }

    function mintGeneral(address to, uint256 tokenId, string calldata description, string calldata name, string calldata url) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);
        _mint(to, tokenId);

        tokenMetadata[tokenId] = Metadata(description, name, url);

        emit Transfer(address(0), to, tokenId);
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
}
