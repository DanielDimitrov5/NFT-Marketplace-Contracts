// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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

    /**
     * @dev Adds a new NFT collection to the marketplace.
     * @param _nftCollection The address of the NFT collection contract.
     */
    function addCollection(address _nftCollection) external {
        if (isCollectionAdded[_nftCollection])
            revert Marketplace__CollectionAlreadyAdded(_nftCollection);

        collectionCount.increment();

        collections[collectionCount.current()] = _nftCollection;
        isCollectionAdded[_nftCollection] = true;

        emit LogCollectionAdded(collectionCount.current(), _nftCollection);
    }

    /**
     * @dev Adds an NFT to the marketplace.
     * @param _collectionId The ID of the NFT collection to which the NFT belongs.
     * @param _tokenId The token ID of the NFT to be added.
     */
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

    /**
     * @dev Lists an NFT for sale in the marketplace.
     * @param _itemId The ID of the item to be listed.
     * @param _price The price at which the item should be listed.
     */
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

    /**
     * @dev Allows a buyer to purchase an item listed for sale.
     * @param _itemId The ID of the item to be purchased.
     */
    function buyItem(uint256 _itemId) external payable {
        Item storage item = items[_itemId];

        if (item.id == 0)
            revert Marketplace__ItemWithThisIdDoesNotExist(_itemId);

        if (item.price == 0)
            revert Marketplace__ThisItemIsNotListedForSale(_itemId);

        if (item.price > msg.value) revert Marketplace__NotEnoughtFunds();

        if (item.owner == msg.sender)
            revert Marketplace__YouCannotBuyYourOwnItem();

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

        item.price = 0;
        item.owner = msg.sender;

        IERC721(item.nftContract).safeTransferFrom(
            seller,
            msg.sender,
            item.tokenId
        );

        emit LogItemSold(
            _itemId,
            item.nftContract,
            item.tokenId,
            seller,
            msg.sender,
            price
        );
    }

    /**
     * @dev Places an offer for an item that is not listed for sale.
     * @param _itemId The ID of the item for which the offer is being placed.
     * @param _price The price being offered for the item.
     */
    function placeOffer(uint256 _itemId, uint256 _price) external {
        Item memory item = items[_itemId];

        if (item.id == 0)
            revert Marketplace__ItemWithThisIdDoesNotExist(_itemId);

        if (item.price != 0) revert Marketplace__ItemAlreadyListed(item.id);

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

    /**
     * @dev Accepts an offer made for an item.
     * @param _itemId The ID of the item for which the offer was made.
     * @param offerer The address of the account that made the offer.
     */
    function acceptOffer(uint256 _itemId, address offerer) external {
        Offer storage offer = offers[_itemId][offerer];

        if (offer.itemId == 0) revert Marketplace__OfferDoesNotExist(_itemId);

        if (offer.seller != msg.sender)
            revert Marketplace__YouAreNotTheOwnerOfThisToken();

        offer.isAccepted = true;

        emit LogOfferAccepted(_itemId, offerer);
    }

    /**
     * @dev Allows a buyer to claim an NFT after their offer has been accepted.
     * @param _itemId The ID of the item to be claimed.
     */
    function claimItem(uint256 _itemId) external payable {
        Offer memory offer = offers[_itemId][msg.sender];

        if (offer.itemId == 0) revert Marketplace__OfferDoesNotExist(_itemId);

        if (offer.isAccepted == false)
            revert Marketplace__OfferIsNotAccepted(_itemId);

        if (offer.price > msg.value) revert Marketplace__NotEnoughtFunds();

        offer.seller.transfer(offer.price);

        Item storage item = items[_itemId];
        item.owner = msg.sender;

        delete offers[_itemId][msg.sender];
        delete itemOfferers[_itemId];

        IERC721(offer.nftContract).safeTransferFrom(
            offer.seller,
            msg.sender,
            offer.tokenId
        );

        emit LogItemClaimed(_itemId, msg.sender);
    }

    /**
     * @dev Allows the contract owner to withdraw the balance of the contract.
     */
    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * @dev Generates a unique hash for an NFT based on its contract address and token ID.
     * @param _nftContract The address of the NFT contract.
     * @param _tokenId The token ID of the NFT.
     * @return A bytes32 hash uniquely representing the NFT.
     */
    function getHash(
        address _nftContract,
        uint256 _tokenId
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_nftContract, _tokenId));
    }

    /**
     * @dev Retrieves the addresses of accounts that have made offers for a specific item.
     * @param itemId The ID of the item.
     * @return An array of addresses that have made offers for the item.
     */
    function getOfferers(
        uint256 itemId
    ) external view returns (address[] memory) {
        return itemOfferers[itemId];
    }

    receive() external payable {}
}
