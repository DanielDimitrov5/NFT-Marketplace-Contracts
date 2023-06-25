// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

error Marketplace__CollectionAlreadyAdded(address nftCollection);
error Marketplace__CollectionIsNotAdded();
error Marketplace__ItemWithThisIdDoesNotExist(uint256 id);
error Marketplace__YouAreNotTheOwnerOfThisToken();
error Marketplace__ItemAlreadyAdded();
error Marketplace__ItemAlreadyListed(uint256 id);
error Marketplace__ThisItemIsNotListedForSale(uint256 id);
error Marketplace__NotEnoughtFunds();
error Marketplace__ThisItemIsListedForSale();
error Marketplace__YouCannotBuyYourOwnItem();
error Marketplace__YouAlreadyMadeAnOffer();
error Marketplace__OfferDoesNotExist(uint256 id);
error Marketplace__YouAreNotTheOwnerOfThisOffer(uint256 id);
error Marketplace__YouCannotPlaceAnOfferOnYourOwnItem(uint256 id);
error Marketplace__PriceCannotBeZero();
error Marketplace__OfferIsNotAccepted(uint256 id);

contract Marketplace is Ownable {
    using Counters for Counters.Counter;

    uint8 public immutable feePercent;

    Counters.Counter public itemCount;
    Counters.Counter public collectionCount;

    constructor(uint8 _feePercent) {
        feePercent = _feePercent;
    }

    mapping(uint256 => address) public collections;
    mapping(address => bool) private isCollectionAdded;

    mapping(uint256 => Item) public items;
    mapping(bytes32 => bool) private isItemAdded;

    mapping(uint256 => mapping(address => Offer)) public offers;
    mapping(uint256 => address[]) public itemOfferers;

    struct Item {
        uint256 id;
        address nftContract;
        uint256 tokenId;
        address owner;
        uint256 price;
    }

    struct Offer {
        uint256 itemId;
        address nftContract;
        uint256 tokenId;
        address payable seller;
        uint256 price;
        bool isAccepted;
    }

    event LogCollectionAdded(uint256 id, address indexed nftCollection);

    event LogItemAdded(
        uint256 id,
        address indexed nftContract,
        uint256 tokenId,
        address indexed owner
    );

    event LogItemListed(
        uint256 id,
        address indexed nftContract,
        uint256 tokenId,
        address indexed seller,
        uint256 price
    );

    event LogItemSold(
        uint256 id,
        address indexed nftContract,
        uint256 tokenId,
        address indexed seller,
        address indexed buyer,
        uint256 price
    );

    event LogOfferPlaced(
        uint256 id,
        address indexed nftContract,
        uint256 tokenId,
        address indexed buyer,
        uint256 price
    );

    event LogOfferAccepted(uint256 indexed id, address indexed offerer);

    event LogItemClaimed(uint256 indexed id, address indexed claimer);

    function addCollection(address _nftCollection) external {
        if (isCollectionAdded[_nftCollection])
            revert Marketplace__CollectionAlreadyAdded(_nftCollection);

        collectionCount.increment();

        collections[collectionCount.current()] = _nftCollection;
        isCollectionAdded[_nftCollection] = true;

        emit LogCollectionAdded(collectionCount.current(), _nftCollection);
    }

    function addItem(uint256 _collectionId, uint256 _tokenId) external {
        address nftCollection = collections[_collectionId];

        if (!isCollectionAdded[nftCollection])
            revert Marketplace__CollectionIsNotAdded();

        bytes32 idHash = getHash(nftCollection, _tokenId);

        if (isItemAdded[idHash]) revert Marketplace__ItemAlreadyAdded();

        if (IERC721(nftCollection).ownerOf(_tokenId) != msg.sender)
            revert Marketplace__YouAreNotTheOwnerOfThisToken();

        itemCount.increment();

        items[itemCount.current()] = Item(
            itemCount.current(),
            nftCollection,
            _tokenId,
            msg.sender,
            0
        );

        isItemAdded[idHash] = true;

        emit LogItemAdded(
            itemCount.current(),
            nftCollection,
            _tokenId,
            msg.sender
        );
    }

    function listItem(uint256 _itemId, uint256 _price) external {
        Item storage item = items[_itemId];

        if (item.id == 0)
            revert Marketplace__ItemWithThisIdDoesNotExist(item.id);

        if (item.owner != msg.sender)
            revert Marketplace__YouAreNotTheOwnerOfThisToken();

        if (_price == 0) revert Marketplace__PriceCannotBeZero();

        if (item.price != 0) revert Marketplace__ItemAlreadyListed(item.id);

        item.price = _price;

        emit LogItemListed(
            _itemId,
            item.nftContract,
            item.tokenId,
            msg.sender,
            _price
        );
    }

    function buyItem(uint256 _itemId) external payable {
        Item storage item = items[_itemId];

        if (item.id == 0)
            revert Marketplace__ItemWithThisIdDoesNotExist(_itemId);

        if (item.price == 0)
            revert Marketplace__ThisItemIsNotListedForSale(_itemId);

        if (item.price > msg.value)
            revert Marketplace__NotEnoughtFunds();

        if(item.owner == msg.sender) revert Marketplace__YouCannotBuyYourOwnItem();

        address seller = item.owner;
        uint256 price = item.price;

        uint256 sellerMargin = (price * (100 - feePercent)) / 100;

        if (msg.value > price) {
            uint256 change = msg.value - price;
            payable(msg.sender).transfer(change);
        }

        uint256 fee = item.price - sellerMargin;
        payable(address(this)).transfer(fee);
        payable(item.owner).transfer(item.price - fee);

        IERC721(item.nftContract).safeTransferFrom(
            seller,
            msg.sender,
            item.tokenId
        );

        item.price = 0;
        item.owner = msg.sender;

        emit LogItemSold(
            _itemId,
            item.nftContract,
            item.tokenId,
            seller,
            msg.sender,
            price
        );
    }

    function placeOffer(uint256 _itemId, uint256 _price) external {
        Item memory item = items[_itemId];

        if (item.id == 0)
            revert Marketplace__ItemWithThisIdDoesNotExist(_itemId);

        if (item.price != 0)
            revert Marketplace__ItemAlreadyListed(item.id);

        if (_price == 0) revert Marketplace__PriceCannotBeZero();

        if (item.owner == msg.sender)
            revert Marketplace__YouCannotPlaceAnOfferOnYourOwnItem(_itemId);

        offers[_itemId][msg.sender] = Offer(
            _itemId,
            item.nftContract,
            item.tokenId,
            payable(item.owner),
            _price,
            false
        );

        itemOfferers[_itemId].push(msg.sender);

        emit LogOfferPlaced(
            _itemId,
            item.nftContract,
            item.tokenId,
            msg.sender,
            _price
        );
    }

    function acceptOffer(uint256 _itemid, address offerer) external {
        Offer storage offer = offers[_itemid][offerer];

        if (offer.itemId == 0) revert Marketplace__OfferDoesNotExist(_itemid);

        if (offer.seller != msg.sender)
            revert Marketplace__YouAreNotTheOwnerOfThisToken();

        offer.isAccepted = true;

        emit LogOfferAccepted(_itemid, offerer);
    }

    function claimItem(uint256 _itemid) external payable {
        Offer memory offer = offers[_itemid][msg.sender];

        if (offer.itemId == 0) revert Marketplace__OfferDoesNotExist(_itemid);

        if (offer.isAccepted == false)
            revert Marketplace__OfferIsNotAccepted(_itemid);

        if (offer.price > msg.value) revert Marketplace__NotEnoughtFunds();

        offer.seller.transfer(offer.price);

        IERC721(offer.nftContract).safeTransferFrom(
            offer.seller,
            msg.sender,
            offer.tokenId
        );

        Item storage item = items[_itemid];
        item.owner = msg.sender;

        delete offers[_itemid][msg.sender];
        delete itemOfferers[_itemid];

        emit LogItemClaimed(_itemid, msg.sender);
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function getHash(
        address _nftContract,
        uint256 _tokenId
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_nftContract, _tokenId));
    }

    function getOfferers(uint256 itemId) external view returns(address[] memory) {
        return itemOfferers[itemId];
    }

    receive() external payable {}
}
