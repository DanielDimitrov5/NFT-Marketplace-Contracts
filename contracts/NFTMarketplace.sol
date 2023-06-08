// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

error Marketplace__CollectionAlreadyAdded(IERC721 nftCollection);
error Marketplace__CollectionIsNotAdded();
error Marketplace__ItemWithThisIdDoesNotExist(uint256 id);
error Marketplace__YouAreNotTheOwnerOfThisToken();
error Marketplace__ItemAlreadyAdded();
error Marketplace__ItemAlreadyListed(bytes32 id);
error Marketplace__ThisItemIsNotListedForSale(uint256 id);
error Marketplace__NotEnoughtFunds();
error Marketplace__ThisItemIsListedForSale();
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

    mapping(uint256 => IERC721) public collections;
    mapping(IERC721 => bool) private isCollectionAdded;

    mapping(uint256 => Item) public items;
    mapping(bytes32 => bool) private isItemAdded;

    mapping(bytes32 => ListedItems) public listedItems;

    mapping(uint256 => mapping(address => Offer)) public offers;
    mapping(uint256 => address[]) public itemOfferers;

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

    struct Offer {
        uint256 itemId;
        IERC721 nftContract;
        uint256 tokenId;
        address payable seller;
        uint256 price;
        bool isAccepted;
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

    event LogOfferPlaced(
        uint256 id,
        IERC721 indexed nftContract,
        uint256 tokenId,
        address indexed buyer,
        uint256 price
    );

    event LogOfferAccepted(
        uint256 indexed id,
        address indexed offerer
    );

    event LogItemClaimed(
        uint256 indexed id,
        address indexed claimer
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

        if (isCollectionAdded[nftCollection] == false)
            revert Marketplace__CollectionIsNotAdded();

        bytes32 idHash = getHash(nftCollection, _tokenId);

        if (isItemAdded[idHash]) revert Marketplace__ItemAlreadyAdded();

        if (nftCollection.ownerOf(_tokenId) != msg.sender)
            revert Marketplace__YouAreNotTheOwnerOfThisToken();

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

    function listItem(uint256 _itemId, uint256 _price) external {
        Item memory item = items[_itemId];

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
            _itemId,
            item.nftContract,
            item.tokenId,
            msg.sender,
            _price
        );
    }

    function buyItem(uint256 _itemId) external payable {
        Item storage item = items[_itemId];

        if (item.id == 0) revert Marketplace__ItemWithThisIdDoesNotExist(_itemId);

        bytes32 idHash = getHash(item.nftContract, item.tokenId);

        ListedItems memory listedItem = listedItems[idHash];

        if (listedItem.id == 0)
            revert Marketplace__ThisItemIsNotListedForSale(_itemId);

        if (listedItem.price > msg.value) //???
            revert Marketplace__NotEnoughtFunds();

        listedItem.nftContract.safeTransferFrom(
            listedItem.seller,
            msg.sender,
            listedItem.tokenId
        );

        uint256 sellerMargin = listedItem.price * (100 - feePercent) / 100;

        if (msg.value > listedItem.price) {
            uint256 change = msg.value - listedItem.price;
            payable(msg.sender).transfer(change);
        }

        uint256 fee = listedItem.price - sellerMargin;
        payable(address(this)).transfer(fee);
        payable(item.owner).transfer(listedItem.price - fee);

        delete listedItems[idHash];

        item.owner = msg.sender;

        emit LogItemSold(
            _itemId,
            item.nftContract,
            item.tokenId,
            listedItem.seller,
            msg.sender,
            listedItem.price
        );
    }

    // Offers
    //
    function placeOffer(uint256 _itemId, uint256 _price) external {
        Item memory item = items[_itemId];

        if (item.id == 0)
            revert Marketplace__ItemWithThisIdDoesNotExist(_itemId);

        bytes32 idHash = getHash(item.nftContract, item.tokenId);

        if (listedItems[idHash].id != 0)
            revert Marketplace__ItemAlreadyListed(idHash);

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

        // item.nftContract.approve(address(this), item.tokenId);

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

        offer.nftContract.safeTransferFrom(
            offer.seller,
            msg.sender,
            offer.tokenId
        );

        delete offers[_itemid][msg.sender];
        delete itemOfferers[_itemid];

        emit LogItemClaimed(
            _itemid,
            msg.sender
        );
    }
    //
    // Offers

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function getHash(
        IERC721 _nftContract,
        uint256 _tokenId
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_nftContract, _tokenId));
    }

    receive() external payable {}
}
