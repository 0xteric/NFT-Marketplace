// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MarketplaceCore.sol";

contract Bids is MarketplaceCore {
    constructor(uint _initialFee) MarketplaceCore(_initialFee) {}

    /**
     * Adds a buy order for any token id of the selected collection, needs the buy amount to be sent
     * @param _collection collection address
     * @param _price bid price
     * @param _quantity amount of tokens to buy
     */

    function bidCollection(address _collection, uint _price, uint _quantity) public payable {
        require(msg.value == _price * _quantity, "Marketplace: Incorrect ETH");
        require(collections[_collection].exists, "Collection not registered");
        require(_price > 0 && _quantity > 0, "Marketplace: price and quantity cannot be zero");
        require(_collection != address(0), "Marketplace: collection must exists");
        require(collectionBids[_collection][msg.sender].price == 0, "Marketplace: collection already bidded");

        CollectionBid memory _collectionBid = CollectionBid({bidder: msg.sender, quantity: _quantity, price: _price});

        collectionBids[_collection][msg.sender] = _collectionBid;

        emit CollectionBidCreated(msg.sender, _collection, _quantity, _price);
    }

    /**
     * Cancels an active collection bid, returning the value to the owner
     * @param _collection collection address
     */
    function cancelCollectionBid(address _collection) external nonReentrant {
        CollectionBid memory _bid = collectionBids[_collection][msg.sender];
        require(_bid.bidder == msg.sender, "Marketplace: not bidder");
        delete collectionBids[_collection][msg.sender];

        (bool success, ) = msg.sender.call{value: _bid.price * _bid.quantity}("");
        require(success, "Transfer failed!");
        emit CollectionBidCancelled(msg.sender, _collection);
    }

    /**
     * Accepts a collection bid selling the token to the bidder
     * @param _collection collection address
     * @param _bidder bidder address
     * @param _tokensId token id list
     */
    function acceptCollectionBid(address _collection, address _bidder, uint[] calldata _tokensId) external nonReentrant {
        Collection storage col = collections[_collection];

        require(col.exists, "Collection not registered");
        require(IERC721(_collection).isApprovedForAll(msg.sender, address(this)), "Marketplace: collection not approved");

        CollectionBid memory _bid = collectionBids[_collection][_bidder];
        require(_bid.quantity >= _tokensId.length, "Marketplace: quantity exceeds bid");

        if (_bid.quantity == _tokensId.length) {
            delete collectionBids[_collection][_bidder];
        } else {
            collectionBids[_collection][_bidder].quantity -= _tokensId.length;
        }

        for (uint i = 0; i < _tokensId.length; ) {
            require(IERC721(_collection).ownerOf(_tokensId[i]) == msg.sender, "Not token owner");

            if (listings[_collection][_tokensId[i]].price > 0) {
                Listing memory old = listings[_collection][_tokensId[i]];
                delete listings[_collection][_tokensId[i]];
                totalListings -= 1;
                emit ListingCancelled(old.id, _collection, _tokensId[i], msg.sender, old.price);
            }

            IERC721(_collection).safeTransferFrom(msg.sender, _bid.bidder, _tokensId[i]);

            totalSales += 1;
            col.totalSales += 1;
            col.totalVolume += _bid.price;
            emit BidSold(_collection, _tokensId[i], msg.sender, _bid.bidder, _bid.price, marketplaceFee, col.royaltyFee);
            unchecked {
                ++i;
            }
        }

        _distributePayments(_bid.price * _tokensId.length, col.royaltyReceiver, col.royaltyFee, msg.sender);
    }

    /**
     * Creates a buy order for an specific token, needs the buy amount to be sent
     * @param _collection token address
     * @param _tokenId token id
     * @param _price order price
     */
    function bidToken(address _collection, uint _tokenId, uint _price) public payable {
        require(msg.value == _price, "Marketplace: Incorrect ETH");
        _bidToken(_collection, _tokenId, _price);
    }

    /**
     * Creates a buy order for an specific token, needs the buy amount to be sent
     * @param _collection token address
     * @param _tokenId token id
     * @param _price order price
     */
    function _bidToken(address _collection, uint _tokenId, uint _price) internal {
        require(collections[_collection].exists, "Collection not registered");
        require(_collection != address(0) && _price > 0, "Marketplace: collection and price should exist");
        require(tokenBids[_collection][_tokenId][msg.sender].price == 0, "Marketplace: Bid already exists");

        TokenBid memory _tokenBid = TokenBid({bidder: msg.sender, tokenId: _tokenId, price: _price});

        tokenBids[_collection][_tokenId][msg.sender] = _tokenBid;

        emit TokenBidCreated(msg.sender, _collection, _tokenId, _price);
    }

    /**
     * Creates a buy order for an specific token, needs the buy amount to be sent
     * @param _collection token address
     * @param _tokenIds tokens ids array
     * @param _prices orders price array
     */
    function bidTokenBatch(address _collection, uint[] calldata _tokenIds, uint[] calldata _prices) external payable {
        require(_tokenIds.length == _prices.length, "Length mismatch");
        uint _totalPrice;

        for (uint i = 0; i < _prices.length; ) {
            _totalPrice += _prices[i];
            unchecked {
                ++i;
            }
        }

        require(msg.value == _totalPrice, "Marketplace: Incorrect ETH");

        for (uint i = 0; i < _tokenIds.length; ) {
            _bidToken(_collection, _tokenIds[i], _prices[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * Accepts a buy order for the specific token
     * @param _collection token address
     * @param _bidder bidder address
     * @param _tokenId token id
     */
    function acceptTokenBid(address _collection, address _bidder, uint _tokenId) external nonReentrant {
        TokenBid memory _tokenBid = tokenBids[_collection][_tokenId][_bidder];
        require(_tokenBid.price > 0, "Marketplace: bid doesn't exists");
        require(IERC721(_collection).ownerOf(_tokenId) == msg.sender, "Marketplace: Not owner");
        require(IERC721(_collection).isApprovedForAll(msg.sender, address(this)), "Marketplace: collection not approved");
        Collection storage col = collections[_collection];

        if (listings[_collection][_tokenId].price > 0) {
            Listing memory old = listings[_collection][_tokenId];
            delete listings[_collection][_tokenId];
            totalListings -= 1;
            emit ListingCancelled(old.id, _collection, _tokenId, msg.sender, old.price);
        }

        delete tokenBids[_collection][_tokenId][_bidder];

        IERC721(_collection).safeTransferFrom(msg.sender, _bidder, _tokenId);

        _distributePayments(_tokenBid.price, col.royaltyReceiver, col.royaltyFee, msg.sender);

        totalSales += 1;
        col.totalSales += 1;
        col.totalVolume += _tokenBid.price;
        emit BidSold(_collection, _tokenId, msg.sender, _bidder, _tokenBid.price, marketplaceFee, col.royaltyFee);
    }

    /**
     * Cancels an active token bid, returning the value to the owner
     * @param _collection token address
     * @param _tokenId token id
     */
    function cancelTokenBid(address _collection, uint _tokenId) public nonReentrant {
        TokenBid memory _tokenBid = tokenBids[_collection][_tokenId][msg.sender];
        require(_tokenBid.price > 0, "Marketplace: bid not exists");

        delete tokenBids[_collection][_tokenId][msg.sender];

        (bool success, ) = msg.sender.call{value: _tokenBid.price}("");
        require(success, "Cancel token bid transfer failed");
        emit TokenBidCancelled(_tokenBid.bidder, _collection, _tokenId);
    }

    /**
     * Cancels an active token bid, returning the value to the owner
     * @param _collections token addresses array
     * @param _tokenIds token ids array
     */
    function cancelTokenBidBatch(address[] calldata _collections, uint[] calldata _tokenIds) external {
        require(_collections.length == _tokenIds.length, "Length mismatch");

        for (uint i = 0; i < _collections.length; ) {
            cancelTokenBid(_collections[i], _tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }
}
