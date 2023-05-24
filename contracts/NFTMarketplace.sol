// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

error Marketplace__ItemWithThisIdDoesNotExist();
error Marketplace__YouAreNotTheOwnerOfThisToken();
error Marketplace__ItemAlreadyListed(bytes32 id);

contract Marketplace {
    using Counters for Counters.Counter;

    address payable public immutable feeAccount;
    uint8 public immutable feePercent;

    Counters.Counter public itemCount;

    constructor(address payable _feeAccount, uint8 _feePercent) {
        feeAccount = _feeAccount;
        feePercent = _feePercent;
    }

    mapping(uint256 => Item) public items;
    mapping(bytes32 => ListedItems) public listedItems;

    struct Item {
        uint256 id;
        IERC721 nftContract;
        uint256 tokenId;
        address owner;
    }

    struct ListedItems {
        bytes32 id;
        IERC721 nftContract;
        uint256 tokenId;
        address payable seller;
        uint256 price;
    }

    event LogItemAdded(
        uint256 id,
        IERC721 indexed nftContract,
        uint256 tokenId,
        address indexed owner
    );

    event LogItemListed(
        bytes32 id,
        IERC721 indexed nftContract,
        uint256 tokenId,
        address indexed seller,
        uint256 price
    );

    function addItem(IERC721 _nftContract, uint256 _tokenId) external {
        if(_nftContract.ownerOf(_tokenId) != msg.sender) revert Marketplace__YouAreNotTheOwnerOfThisToken();

        itemCount.increment();

        items[itemCount.current()] = Item(
            itemCount.current(),
            _nftContract,
            _tokenId,
            msg.sender
        );

        emit LogItemAdded(
            itemCount.current(),
            _nftContract,
            _tokenId,
            msg.sender
        );
    }

    function listItem(uint256 id, uint256 _price) external {
        Item memory item = items[id];

        if(item.id == 0) revert Marketplace__ItemWithThisIdDoesNotExist();

        if(item.owner != msg.sender) revert Marketplace__YouAreNotTheOwnerOfThisToken();

        bytes32 idHash = getHash(item.nftContract, item.tokenId);
        
        if(listedItems[idHash].id == idHash) revert Marketplace__ItemAlreadyListed(idHash);

        listedItems[idHash] = ListedItems(
            idHash,
            item.nftContract,
            item.tokenId,
            payable(msg.sender),
            _price
        );

        // item.nftContract.approve(address(this), item.tokenId);

        emit LogItemListed(
            idHash,
            item.nftContract,
            item.tokenId,
            msg.sender,
            _price
        );
    }

    function getHash(IERC721 _nftContract, uint256 _tokenId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_nftContract, _tokenId));
    }
}
