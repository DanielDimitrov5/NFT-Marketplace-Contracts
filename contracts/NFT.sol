// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract NFT is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter public tokenCount;

    event LogNftMinted(uint256 id, address indexed owner, string tokenURI);

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    /**
     * @dev Safely mints NFT to the sender and sets the provided `_tokenURI` as metadata.
     */
    function mint(string memory _tokenURI) external onlyOwner returns (uint256) {
        tokenCount.increment();

        _safeMint(msg.sender, tokenCount.current());
        _setTokenURI(tokenCount.current(), _tokenURI);

        emit LogNftMinted(tokenCount.current(), msg.sender, _tokenURI);

        return tokenCount.current();
    }
}