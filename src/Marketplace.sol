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

    mapping(address => mapping(uint => Listing)) public listings;

    event List(address indexed seller, address indexed collection, uint tokenId, uint price);
    event CancelList(address indexed seller, address indexed collection, uint tokenId);
    event Sale(address indexed seller, address indexed buyer, uint tokenId);

    constructor() Ownable(msg.sender) {}

    function list(address _collection, uint _tokenId, uint _price) external {
        require(_price > 0, "Price must be greater");
        require(IERC721(_collection).ownerOf(_tokenId) == msg.sender, "Not owner");

        Listing memory newListing = Listing({collection: _collection, seller: msg.sender, tokenId: _tokenId, price: _price});

        listings[_collection][_tokenId] = newListing;

        emit List(msg.sender, _collection, _tokenId, _price);
    }

    function cancelList(address _collection, uint _tokenId) external {
        require(listings[_collection][_tokenId].seller == msg.sender, "Not owner");

        delete listings[_collection][_tokenId];

        emit CancelList(msg.sender, _collection, _tokenId);
    }

    function buy(address _collection, uint _tokenId) external payable nonReentrant {
        Listing memory _listing = listings[_collection][_tokenId];
        require(_listing.price > 0, "Listing not exists");
        require(msg.value == _listing.price, "Insufficient value");

        delete listings[_collection][_tokenId];

        (bool success, ) = _listing.seller.call{value: _listing.price}("");
        require(success, "Transfer failed");

        IERC721(_collection).safeTransferFrom(_listing.seller, msg.sender, _listing.tokenId);
        emit Sale(_listing.seller, msg.sender, _tokenId);
    }
}
