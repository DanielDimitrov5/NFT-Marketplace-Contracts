![Architecture diagram](/Architecture.drawio.png);

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
