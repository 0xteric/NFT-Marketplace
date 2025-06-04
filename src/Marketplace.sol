// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract Marketplace is Ownable, ReentrancyGuard {
    struct Listing {
        address collection;
        address seller;
        uint tokenId;
        uint price;
    }

    struct CollectionBid {
        address collection;
        address bidder;
        uint quantity;
        uint price;
    }

    uint public marketplaceFee;
    uint public basicPoints = 10000;
    address public feeReceiver;

    mapping(address => mapping(uint => Listing)) public listings;
    mapping(address => mapping(address => CollectionBid)) public bids;

    event List(address indexed seller, address indexed collection, uint tokenId, uint price);
    event CancelList(address indexed seller, address indexed collection, uint tokenId);
    event Bid(address indexed bidder, address indexed collection, uint price);
    event CancelBid(address indexed bidder, address indexed collection);
    event Sale(address indexed seller, address indexed buyer, uint tokenId);

    constructor(uint _initialFee) Ownable(msg.sender) {
        marketplaceFee = _initialFee;
        feeReceiver = msg.sender;
    }

    function list(address _collection, uint _tokenId, uint _price) external {
        require(_price > 0, "Price must be greater");
        require(IERC721(_collection).ownerOf(_tokenId) == msg.sender, "Not owner");
        require(IERC721(_collection).isApprovedForAll(msg.sender, address(this)), "Marketplace: collection not approved");

        Listing memory newListing = Listing({collection: _collection, seller: msg.sender, tokenId: _tokenId, price: _price});

        listings[_collection][_tokenId] = newListing;

        emit List(msg.sender, _collection, _tokenId, _price);
    }

    function cancelList(address _collection, uint _tokenId) external {
        require(listings[_collection][_tokenId].seller == msg.sender, "Not owner");

        delete listings[_collection][_tokenId];

        emit CancelList(msg.sender, _collection, _tokenId);
    }

    function bidCollection(address _collection, uint _price, uint _quantity) external payable {
        require(_price > 0 && _quantity > 0, "Marketplace: price and quantity cannot be zero");
        require(_collection != address(0), "Marketplace: collection must exists");
        require(msg.value >= _price * _quantity, "Marketplace: add size to your bid");
        require(bids[_collection][msg.sender].price == 0, "Marketplace: collection already bidded");

        CollectionBid memory _collectionBid = CollectionBid({collection: _collection, bidder: msg.sender, quantity: _quantity, price: _price});

        bids[_collection][msg.sender] = _collectionBid;

        emit Bid(msg.sender, _collection, _price);
    }

    function cancelBid(address _collection) external nonReentrant {
        CollectionBid memory _bid = bids[_collection][msg.sender];
        require(_bid.bidder == msg.sender, "Marketplace: not bidder");
        delete bids[_collection][msg.sender];

        (bool success, ) = msg.sender.call{value: _bid.price * _bid.quantity}("");
        require(success, "Transfer failed!");
        emit CancelBid(msg.sender, _collection);
    }

    function acceptBid(address _collection, address _bidder, uint[] calldata _tokensId) external nonReentrant {
        CollectionBid memory _bid = bids[_collection][_bidder];
        require(_bid.quantity >= _tokensId.length, "Marketplace: quantity exceeds bid");
        require(IERC721(_collection).balanceOf(msg.sender) >= _tokensId.length, "Marketplace: not enough balance");
        require(IERC721(_collection).isApprovedForAll(msg.sender, address(this)), "Marketplace: collection not approved");

        if (_bid.quantity == _tokensId.length) {
            delete bids[_collection][_bidder];
        } else {
            bids[_collection][_bidder].quantity -= _tokensId.length;
        }

        for (uint i = 0; i < _tokensId.length; i++) {
            IERC721(_collection).safeTransferFrom(msg.sender, _bid.bidder, _tokensId[i]);
        }

        uint fee = (_bid.price * _tokensId.length * marketplaceFee) / basicPoints;
        uint payment = _bid.price * _tokensId.length - fee;

        (bool _success, ) = msg.sender.call{value: payment}("");
        require(_success, "Accept bid pay transfer failed!");

        (bool __success, ) = feeReceiver.call{value: fee}("");
        require(__success, "Accept bid fee transfer failed!");
    }

    function buy(address _collection, uint _tokenId) external payable nonReentrant {
        Listing memory _listing = listings[_collection][_tokenId];
        require(_listing.price > 0, "Listing not exists");
        require(msg.value == _listing.price, "Insufficient value");

        delete listings[_collection][_tokenId];

        uint fee = ((_listing.price * marketplaceFee) / basicPoints);
        uint payment = _listing.price - fee;

        (bool _success, ) = _listing.seller.call{value: payment}("");
        require(_success, "Buy pay transfer failed");

        (bool __success, ) = feeReceiver.call{value: fee}("");
        require(__success, "Buy fee transfer failed");

        IERC721(_collection).safeTransferFrom(_listing.seller, msg.sender, _listing.tokenId);
        emit Sale(_listing.seller, msg.sender, _tokenId);
    }

    function updateMarketplaceFee(uint _newFee) external onlyOwner {
        marketplaceFee = _newFee;
    }
}
