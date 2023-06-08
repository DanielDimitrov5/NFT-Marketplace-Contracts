# NFT Marketplace 

## User stories

- **User:** Account willing to register NFT collections, sell or buy NFT.
- **Seller:** User who can add and list his NFTs or accept offers for his non-listed items on the Marketplace.
- **Buyer:** User who can buy listed items or place offers for other users' non-listed items.
- **Marketplace:** Smart contract which handles operations like adding, listing, buying, etc.
- **NFT:** ERC721 Smart contract which is considered a **collection** in the context of this project.
- **Item:** Structure on the Marketplace that represents NFTs with price and other useful properies.
- **Offer:** Structure that represents offer for non-listed item.
- **Owner:** Owner of the contract. He can withdraw the accumulated money from the Marketplace contract.

![User stories](/readme/UserStories.drawio.png)

![Architecture diagram](/readme/Architecture.drawio.png)

| Function      | Parameters                                | Visibility & Modifiers | Description                                                                                                                                |
| ------------- | ----------------------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| addCollection | IERC721  _nftCollection                   | external               | User registers collection to the Marketplace                                                                                               |
| addItem       | uint256 \_collectionId, uitn256 \_tokenId | external               | The user adds NFT to the Marketplace. Only from registered collections!                                                                    |
| listItem      | uint256 \_itemId, uint256 \_price         | external               | Seller list NFT item for sale. Only if the item is added to the Marketplace!                                                               |
| buyItem       | uint256 \_itemId                          | external, payable      | The buyer buys the listed item, transfers the NFT to the buyer,  pays to the seller, pays fee to the contract. Only if the item is listed! |
| placeOffer    | uint256 \_itemId, uint256 \_price         | external               | Buyer places offer for non-listed item. Only if the item is added to the Marketplace!                                                      |
| acceptOffer   | uint256 \_itemId, address offerer         | external               | The seller accepts a placed offer.                                                                                                         |
| claimItem     | uint256 \_itemId                          | external, payable      | The buyer claims his item if the NFT owner has accepted his offer. It transfers the NFT to the buyer and pays the seller.                  |
| withdraw      | \-                                        | external, OnlyOwner    | The owner withdraws the accumulated fee from the contract.                                                                                 |
