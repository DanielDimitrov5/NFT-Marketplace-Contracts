// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

error Marketplace__CollectionAlreadyAdded(IERC721 nftCollection);
error Marketplace__CollectionIsNotAdded();
error Marketplace__ItemWithThisIdDoesNotExist(uint256 id);
error Marketplace__ThisItemIsNotListedForSale(uint256 id);
error Marketplace__YouAreNotTheOwnerOfThisToken();
error Marketplace__ItemAlreadyAdded();
error Marketplace__ItemAlreadyListed(bytes32 id);
error Marketplace__NotEnoughtFunds();

contract Marketplace is Ownable {
    using Counters for Counters.Counter;

    address payable public immutable feeAccount;
    uint8 public immutable feePercent;

    Counters.Counter public itemCount;
    Counters.Counter public collectionCount;

    constructor(address payable _feeAccount, uint8 _feePercent) {
        feeAccount = _feeAccount;
        feePercent = _feePercent;
    }

    mapping(uint256 => IERC721) public collections;
    mapping(IERC721 => bool) private isCollectionAdded;

    mapping(uint256 => Item) public items;
    mapping(bytes32 => bool) private isItemAdded;

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

    event LogCollectionAdded(uint256 id, IERC721 indexed nftCollection);

    event LogItemAdded(
        uint256 id,
        IERC721 indexed nftContract,
        uint256 tokenId,
        address indexed owner
    );

    event LogItemListed(
        uint256 id,
        IERC721 indexed nftContract,
        uint256 tokenId,
        address indexed seller,
        uint256 price
    );

    event LogItemSold(
        uint256 id,
        IERC721 indexed nftContract,
        uint256 tokenId,
        address indexed seller,
        address indexed buyer,
        uint256 price
    );

    function addCollection(IERC721 _nftCollection) external {
        if (isCollectionAdded[_nftCollection])
            revert Marketplace__CollectionAlreadyAdded(_nftCollection);

        collectionCount.increment();

        collections[collectionCount.current()] = _nftCollection;
        isCollectionAdded[_nftCollection] = true;

        emit LogCollectionAdded(collectionCount.current(), _nftCollection);
    }

    function addItem(uint256 _collectionId, uint256 _tokenId) external {
        IERC721 nftCollection = collections[_collectionId];

        if (isCollectionAdded[nftCollection] == false) revert Marketplace__CollectionIsNotAdded();

        bytes32 idHash = getHash(nftCollection, _tokenId);
        
        if (isItemAdded[idHash]) revert Marketplace__ItemAlreadyAdded();

        if (nftCollection.ownerOf(_tokenId) != msg.sender) revert Marketplace__YouAreNotTheOwnerOfThisToken();


        itemCount.increment();

        items[itemCount.current()] = Item(
            itemCount.current(),
            nftCollection,
            _tokenId,
            msg.sender
        );

        isItemAdded[idHash] = true;

        emit LogItemAdded(
            itemCount.current(),
            nftCollection,
            _tokenId,
            msg.sender
        );
    }

    function listItem(uint256 id, uint256 _price) external {
        Item memory item = items[id];

        if (item.id == 0)
            revert Marketplace__ItemWithThisIdDoesNotExist(item.id);

        if (item.owner != msg.sender)
            revert Marketplace__YouAreNotTheOwnerOfThisToken();

        bytes32 idHash = getHash(item.nftContract, item.tokenId);

        if (listedItems[idHash].id == idHash)
            revert Marketplace__ItemAlreadyListed(idHash);

        listedItems[idHash] = ListedItems(
            idHash,
            item.nftContract,
            item.tokenId,
            payable(msg.sender),
            _price
        );

        // item.nftContract.approve(address(this), item.tokenId);

        emit LogItemListed(
            id,
            item.nftContract,
            item.tokenId,
            msg.sender,
            _price
        );
    }

    function buyItem(uint256 _id) external payable {
        Item storage item = items[_id];

        if (item.id == 0) revert Marketplace__ItemWithThisIdDoesNotExist(_id);

        bytes32 idHash = getHash(item.nftContract, item.tokenId);

        ListedItems memory listedItem = listedItems[idHash];

        if (listedItem.id == 0)
            revert Marketplace__ThisItemIsNotListedForSale(_id);

        if (getTotalPrice(_id) > msg.value)
            revert Marketplace__NotEnoughtFunds();

        listedItem.nftContract.safeTransferFrom(
            listedItem.seller,
            msg.sender,
            listedItem.tokenId
        );

        uint256 totalPrice = getTotalPrice(_id);

        if (msg.value > totalPrice) {
            uint256 change = msg.value - totalPrice;
            payable(msg.sender).transfer(change);
        }

        uint256 fee = totalPrice - listedItem.price;
        payable(address(this)).transfer(fee);
        payable(item.owner).transfer(listedItem.price);

        delete listedItems[idHash];

        item.owner = msg.sender;

        emit LogItemSold(
            _id,
            item.nftContract,
            item.tokenId,
            listedItem.seller,
            msg.sender,
            listedItem.price
        );
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function getTotalPrice(uint256 _id) public view returns (uint256) {
        Item memory item = items[_id];

        if (item.id == 0) revert Marketplace__ItemWithThisIdDoesNotExist(_id);

        bytes32 idHash = getHash(item.nftContract, item.tokenId);

        ListedItems memory listedItem = listedItems[idHash];

        if (listedItem.id == 0)
            revert Marketplace__ThisItemIsNotListedForSale(_id);

        return (listedItem.price * (100 + feePercent)) / 100;
    }

    function getHash(
        IERC721 _nftContract,
        uint256 _tokenId
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_nftContract, _tokenId));
    }

    receive() external payable {}
}
