# NFT Marketplace Smart Contract

This contract enables listing, bidding, buying, and selling of ERC721 NFTs with marketplace fees and creator royalties.

---

## ⚙️ Features

- List NFTs for sale at a fixed price
- Cancel listings
- Place and cancel bids on entire collections or individual tokens
- Accept bids and complete sales with automatic payment distribution
- Supports marketplace fees and configurable royalties for NFT creators
- Owner controls marketplace fee, fee receiver, and royalties settings
- Reentrancy guard for secure fund transfers

---

## 📋 Core Structures

- `Listing`: Details of a token listed for sale (collection, seller, tokenId, price)
- `CollectionBid`: Bid on multiple tokens from a collection (bidder, quantity, price)
- `TokenBid`: Bid on a specific token (bidder, tokenId, price)
- `CollectionCreatorFee`: Royalty fee and receiver for a collection

---

## 🔑 Owner Functions

- `updateRoyalties(address _collection, address _collectionOwner, uint _royalty)`
  - Set royalty fee and recipient for a collection (max 20%)
- `updateMarketplaceFee(uint _newFee)`
  - Update marketplace fee (basis points)
- `updateFeeReceiver(address _newReceiver)`
  - Update address that receives marketplace fees

---

## 🛒 Listing & Buying

- `list(address _collection, uint _tokenId, uint _price)`
  - List a token for sale (requires ownership & approval)
- `cancelList(address _collection, uint _tokenId)`
  - Cancel a token listing
- `buy(address _collection, uint _tokenId)`
  - Buy a listed token by paying the exact price

---

## 💰 Bidding

- `bidCollection(address _collection, uint _price, uint _quantity)`
  - Place a bid on multiple tokens in a collection (ETH sent with bid)
- `cancelCollectionBid(address _collection)`
  - Cancel collection bid and refund ETH
- `acceptCollectionBid(address _collection, address _bidder, uint[] calldata _tokensId)`
  - Accept a collection bid and transfer tokens to bidder
- `bidToken(address _collection, uint _tokenId, uint _price)`
  - Place a bid on a specific token
- `cancelTokenBid(address _collection, uint _tokenId)`
  - Cancel a token bid and refund ETH
- `acceptTokenBid(address _collection, address _bidder, uint _tokenId)`
  - Accept a token bid and transfer token to bidder

---

## 💸 Payment Distribution

Internal `_distributePayments` splits payments as follows:

- Marketplace fee to feeReceiver
- Royalty fee to collection creator
- Remaining payment to seller

---

## 🔐 Security

- Uses `ReentrancyGuard` to prevent reentrancy attacks on sensitive functions

---

## 📢 Events

- `List`, `CancelList`, `BidCollection`, `BidToken`, `CancelBid`, `Sale`
- `RoyaltiesUpdated`, `MarketplaceFeeUpdated`, `MarketplaceFeeReceiverUpdated`

---

## 📄 License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).
