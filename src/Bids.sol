// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MarketplaceCore.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Bids is Ownable, ReentrancyGuard {
    struct CollectionBid {
        address bidder;
        uint quantity;
        uint price;
    }
    struct TokenBid {
        address bidder;
        uint tokenId;
        uint price;
    }
    struct Listing {
        uint id;
        address seller;
        uint price;
    }

    struct Collection {
        address collection;
        address royaltyReceiver;
        uint royaltyFee;
        uint totalVolume;
        uint totalSales;
        bool exists;
    }

    mapping(address => mapping(address => CollectionBid)) public collectionBids;
    mapping(address => mapping(uint => mapping(address => TokenBid))) public tokenBids;

    event CollectionBidCreated(address indexed bidder, address indexed collection, uint quantity, uint price);
    event CollectionBidCancelled(address indexed bidder, address indexed collection);
    event TokenBidCreated(address indexed bidder, address indexed collection, uint indexed tokenId, uint price);
    event TokenBidCancelled(address indexed bidder, address indexed collection, uint indexed tokenId);
    event BidSold(address indexed collection, uint256 indexed tokenId, address seller, address buyer, uint256 price, uint256 marketplaceFee, uint256 royaltyFee);

    MarketplaceCore public core;

    modifier onlyMarketplace() {
        require(msg.sender == core.marketplace(), "Not allowed");
        _;
    }

    constructor(address _core) Ownable(msg.sender) {
        core = MarketplaceCore(_core);
    }

    /**
     * Marketplace core contract setter
     * @param _core address
     */
    function setCore(address _core) external onlyMarketplace {
        core = MarketplaceCore(_core);
    }

    /**
     * Adds a buy order for any token id of the selected collection, needs the buy amount to be sent
     * @param _collection collection address
     * @param _price bid price
     * @param _quantity amount of tokens to buy
     */

    function bidCollection(address _collection, uint _price, uint _quantity) external onlyMarketplace {
        (, , , , , bool exists) = core.collections(_collection);
        require(exists, "Collection not registered");
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
    function cancelCollectionBid(address _collection) external nonReentrant onlyMarketplace {
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
    function acceptCollectionBid(address _sender, address _collection, address _bidder, uint[] calldata _tokensId) external nonReentrant onlyMarketplace {
        (, , uint rf, , , bool exists) = core.collections(_collection);

        require(exists, "Collection not registered");
        require(IERC721(_collection).isApprovedForAll(_sender, address(core)), "Marketplace: collection not approved");

        CollectionBid memory _bid = collectionBids[_collection][_bidder];
        require(_bid.quantity >= _tokensId.length, "Marketplace: quantity exceeds bid");

        for (uint i = 0; i < _tokensId.length; ) {
            require(IERC721(_collection).ownerOf(_tokensId[i]) == _sender, "Not token owner");
            (, , uint _price) = core.listings(_collection, _tokensId[i]);
            if (_price > 0) {
                core.removeListing(_collection, _tokensId[i]);
            }

            emit BidSold(_collection, _tokensId[i], _sender, _bid.bidder, _bid.price, core.payments().marketplaceFee(), rf);
            unchecked {
                ++i;
            }
        }

        if (_bid.quantity == _tokensId.length) {
            delete collectionBids[_collection][_bidder];
        } else {
            collectionBids[_collection][_bidder].quantity -= _tokensId.length;
        }
    }

    /**
     * Creates a buy order for an specific token, needs the buy amount to be sent
     * @param _collection token address
     * @param _tokenId token id
     * @param _price order price
     */
    function bidToken(address _sender, address _collection, uint _tokenId, uint _price) external onlyMarketplace {
        _bidToken(_sender, _collection, _tokenId, _price);
    }

    /**
     * Creates a buy order for an specific token, needs the buy amount to be sent
     * @param _collection token address
     * @param _tokenId token id
     * @param _price order price
     */
    function _bidToken(address _sender, address _collection, uint _tokenId, uint _price) internal {
        (, , , , , bool exists) = core.collections(_collection);

        require(exists, "Collection not registered");
        require(_collection != address(0) && _price > 0, "Marketplace: collection and price should exist");
        require(tokenBids[_collection][_tokenId][_sender].price == 0, "Marketplace: Bid already exists");

        TokenBid memory _tokenBid = TokenBid({bidder: _sender, tokenId: _tokenId, price: _price});

        tokenBids[_collection][_tokenId][_sender] = _tokenBid;

        emit TokenBidCreated(_sender, _collection, _tokenId, _price);
    }

    /**
     * Creates a buy order for an specific token, needs the buy amount to be sent
     * @param _collection token address
     * @param _tokenIds tokens ids array
     * @param _prices orders price array
     */
    function bidTokenBatch(address _sender, address _collection, uint[] calldata _tokenIds, uint[] calldata _prices) external onlyMarketplace {
        for (uint i = 0; i < _tokenIds.length; ) {
            _bidToken(_sender, _collection, _tokenIds[i], _prices[i]);
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
    function acceptTokenBid(address _sender, address _collection, address _bidder, uint _tokenId) external nonReentrant onlyMarketplace {
        TokenBid memory _tokenBid = tokenBids[_collection][_tokenId][_bidder];
        require(_tokenBid.price > 0, "Marketplace: bid doesn't exists");
        require(IERC721(_collection).ownerOf(_tokenId) == _sender, "Marketplace: Not owner");
        require(IERC721(_collection).isApprovedForAll(_sender, address(core)), "Marketplace: collection not approved");
        (, , uint rf, , , ) = core.collections(_collection);
        (, , uint _price) = core.listings(_collection, _tokenId);
        if (_price > 0) {
            core.removeListing(_collection, _tokenId);
        }

        delete tokenBids[_collection][_tokenId][_bidder];

        emit BidSold(_collection, _tokenId, _sender, _bidder, _tokenBid.price, core.payments().marketplaceFee(), rf);
    }

    /**
     * Cancels an active token bid, returning the value to the owner
     * @param _collection token address
     * @param _tokenId token id
     */
    function cancelTokenBid(address _sender, address _collection, uint _tokenId) public nonReentrant onlyMarketplace {
        TokenBid memory _tokenBid = tokenBids[_collection][_tokenId][_sender];
        require(_tokenBid.price > 0, "Marketplace: bid not exists");

        delete tokenBids[_collection][_tokenId][_sender];

        bool success = core.payments().refund(_sender, _tokenBid.price);
        require(success, "Cancel token bid transfer failed");
        emit TokenBidCancelled(_tokenBid.bidder, _collection, _tokenId);
    }

    /**
     * Cancels an active token bid, returning the value to the owner
     * @param _collections token addresses array
     * @param _tokenIds token ids array
     */
    function cancelTokenBidBatch(address _sender, address[] calldata _collections, uint[] calldata _tokenIds) external onlyMarketplace {
        require(_collections.length == _tokenIds.length, "Length mismatch");

        for (uint i = 0; i < _collections.length; ) {
            cancelTokenBid(_sender, _collections[i], _tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    function emergencyWithdraw() external onlyOwner nonReentrant {
        uint balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");

        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Withdraw failed");
    }

    receive() external payable {}

    fallback() external payable {}
}
