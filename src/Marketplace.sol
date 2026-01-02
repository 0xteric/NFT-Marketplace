// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract Marketplace is Ownable, ReentrancyGuard {
    struct Listing {
        uint id;
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

    struct TokenBid {
        address collection;
        address bidder;
        uint tokenId;
        uint price;
    }

    struct CollectionCreatorFee {
        uint fee;
        address owner;
    }

    uint public nextListingId;
    uint public marketplaceFee;
    uint public basisPoints = 10000;
    uint public maxRoyaltyFee = 2000;
    address public feeReceiver;

    uint public totalListings;
    uint public totalSales;
    uint public totalVolume;

    mapping(address => mapping(uint => Listing)) public listings;
    mapping(address => mapping(address => CollectionBid)) public collectionBids;
    mapping(address => mapping(uint => mapping(address => TokenBid))) public tokenBids;
    mapping(address => CollectionCreatorFee) public royalties;

    event ListingCreated(uint indexed id, address indexed collection, uint indexed tokenId, address seller, uint price);
    event ListingCancelled(uint indexed id, address indexed collection, uint indexed tokenId, address seller, uint price);
    event ListingSold(uint indexed id, address indexed collection, uint256 indexed tokenId, address seller, address buyer, uint256 price, uint256 marketplaceFee, uint256 royaltyFee);
    event CollectionBidCreated(address indexed bidder, address indexed collection, uint256 quantity, uint256 price);
    event CollectionBidCancelled(address indexed bidder, address indexed collection);
    event TokenBidCreated(address indexed bidder, address indexed collection, uint indexed tokenId, uint price);
    event TokenBidCancelled(address indexed bidder, address indexed collection, uint indexed tokenId);
    event BidSold(address indexed collection, uint256 indexed tokenId, address indexed seller, address buyer, uint256 price, uint256 marketplaceFee, uint256 royaltyFee);
    event RoyaltiesUpdated(address indexed collection, uint fee);
    event MarketplaceFeeUpdated(uint oldFee, uint newFee);
    event MarketplaceFeeReceiverUpdated(address indexed receiver);

    constructor(uint _initialFee) Ownable(msg.sender) {
        marketplaceFee = _initialFee;
        feeReceiver = msg.sender;
    }

    function isListed(address collection, uint tokenId) external view returns (bool) {
        return listings[collection][tokenId].price > 0;
    }

    /**
     * Lists a sell order of a token
     * @param _collection token address
     * @param _tokenId token id
     * @param _price order price
     */
    function list(address _collection, uint _tokenId, uint _price) external {
        require(_price > 0, "Price must be greater");
        require(IERC721(_collection).ownerOf(_tokenId) == msg.sender, "Not owner");
        require(IERC721(_collection).isApprovedForAll(msg.sender, address(this)), "Marketplace: collection not approved");

        uint256 id = nextListingId++;

        if (listings[_collection][_tokenId].price > 0) {
            Listing memory old = listings[_collection][_tokenId];
            delete listings[_collection][_tokenId];
            emit ListingCancelled(old.id, _collection, _tokenId, msg.sender, old.price);
        }

        listings[_collection][_tokenId] = Listing({id: id, collection: _collection, seller: msg.sender, tokenId: _tokenId, price: _price});

        emit ListingCreated(id, _collection, _tokenId, msg.sender, _price);
    }

    /**
     * Cancels an active listing
     * @param _collection token address
     * @param _tokenId token id
     */
    function cancelList(address _collection, uint _tokenId) external {
        require(listings[_collection][_tokenId].seller == msg.sender, "Not owner");

        Listing memory old = listings[_collection][_tokenId];
        delete listings[_collection][_tokenId];

        emit ListingCancelled(old.id, _collection, _tokenId, msg.sender, old.price);
    }

    /**
     * Adds a buy order for any token id of the selected collection, needs the buy amount to be sent
     * @param _collection collection address
     * @param _price offer price
     * @param _quantity amount of tokens to buy
     */

    function bidCollection(address _collection, uint _price, uint _quantity) external payable {
        require(_price > 0 && _quantity > 0, "Marketplace: price and quantity cannot be zero");
        require(_collection != address(0), "Marketplace: collection must exists");
        require(msg.value >= _price * _quantity, "Marketplace: add size to your bid");
        require(collectionBids[_collection][msg.sender].price == 0, "Marketplace: collection already bidded");

        CollectionBid memory _collectionBid = CollectionBid({collection: _collection, bidder: msg.sender, quantity: _quantity, price: _price});

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
        CollectionBid memory _bid = collectionBids[_collection][_bidder];
        require(_bid.quantity >= _tokensId.length, "Marketplace: quantity exceeds bid");
        require(IERC721(_collection).balanceOf(msg.sender) >= _tokensId.length, "Marketplace: not enough balance");
        require(IERC721(_collection).isApprovedForAll(msg.sender, address(this)), "Marketplace: collection not approved");

        if (_bid.quantity == _tokensId.length) {
            delete collectionBids[_collection][_bidder];
        } else {
            collectionBids[_collection][_bidder].quantity -= _tokensId.length;
        }

        for (uint i = 0; i < _tokensId.length; i++) {
            require(IERC721(_collection).ownerOf(_tokensId[i]) == msg.sender);

            if (listings[_collection][_tokensId[i]].price > 0) {
                Listing memory old = listings[_collection][_tokensId[i]];
                delete listings[_collection][_tokensId[i]];
                emit ListingCancelled(old.id, _collection, _tokensId[i], msg.sender, old.price);
            }

            IERC721(_collection).safeTransferFrom(msg.sender, _bid.bidder, _tokensId[i]);

            totalSales += 1;
            emit BidSold(_collection, _tokensId[i], msg.sender, _bid.bidder, _bid.price, marketplaceFee, royalties[_collection].fee);
        }

        _distributePayments(_bid.price * _tokensId.length, _collection, msg.sender);
    }

    /**
     * Creates a buy order for an specific token, needs the buy amount to be sent
     * @param _collection token address
     * @param _tokenId token id
     * @param _price order price
     */
    function bidToken(address _collection, uint _tokenId, uint _price) external payable {
        require(_collection != address(0) && _price > 0, "Marketplace: collection and price should exist");
        require(msg.value >= _price, "Marketplace: add size to bid");
        require(tokenBids[_collection][_tokenId][msg.sender].price == 0, "Marketplace: Bid already exists");

        TokenBid memory _tokenBid = TokenBid({collection: _collection, bidder: msg.sender, tokenId: _tokenId, price: _price});

        tokenBids[_collection][_tokenId][msg.sender] = _tokenBid;

        emit TokenBidCreated(msg.sender, _collection, _tokenId, _price);
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

        if (listings[_collection][_tokenId].price > 0) delete listings[_collection][_tokenId];

        delete tokenBids[_collection][_tokenId][_bidder];

        IERC721(_collection).safeTransferFrom(msg.sender, _bidder, _tokenId);

        _distributePayments(_tokenBid.price, _collection, msg.sender);

        totalSales += 1;

        emit BidSold(_collection, _tokenId, msg.sender, _bidder, _tokenBid.price, marketplaceFee, royalties[_collection].fee);
    }

    /**
     * Cancels an active token bid, returning the value to the owner
     * @param _collection token address
     * @param _tokenId token id
     */
    function cancelTokenBid(address _collection, uint _tokenId) external {
        TokenBid memory _tokenBid = tokenBids[_collection][_tokenId][msg.sender];
        require(_tokenBid.price > 0, "Marketplace: bid not exists");

        delete tokenBids[_collection][_tokenId][msg.sender];

        (bool success, ) = msg.sender.call{value: _tokenBid.price}("");
        require(success, "Cancel token bid transfer failed");
        emit TokenBidCancelled(_tokenBid.bidder, _collection, _tokenId);
    }

    /**
     * Buys a token listed
     * @param _collection token address
     * @param _tokenId token id
     */
    function buy(address _collection, uint _tokenId) external payable nonReentrant {
        Listing memory _listing = listings[_collection][_tokenId];
        require(_listing.price > 0, "Listing not exists");
        require(msg.value == _listing.price, "Insufficient value");

        delete listings[_collection][_tokenId];

        _distributePayments(_listing.price, _collection, _listing.seller);

        IERC721(_collection).safeTransferFrom(_listing.seller, msg.sender, _listing.tokenId);

        totalSales += 1;
        emit ListingSold(_listing.id, _collection, _tokenId, _listing.seller, msg.sender, _listing.price, marketplaceFee, royalties[_collection].fee);
    }

    /**
     * Manages the payment process of every buy/sell transfer
     * @param _price price of the order
     * @param _collection token address
     * @param _to token seller address
     */
    function _distributePayments(uint _price, address _collection, address _to) internal {
        uint fee = (_price * marketplaceFee) / basisPoints;
        uint royalty = (_price * royalties[_collection].fee) / basisPoints;
        uint payment = _price - fee - royalty;

        (bool ok1, ) = feeReceiver.call{value: fee}("");
        require(ok1, "Fee transfer failed");
        (bool ok2, ) = _to.call{value: payment}("");
        require(ok2, "Payment transfer failed");

        if (royalty > 0) {
            require(royalties[_collection].owner != address(0));
            (bool ok3, ) = royalties[_collection].owner.call{value: royalty}("");
            require(ok3, "Royalties transfer failed");
        }

        totalVolume += _price;
    }

    /**
     * Updates the amount and royalties receiver of a collection in basis points
     * @param _collection collection address
     * @param _collectionOwner owner address
     * @param _royalty new royalty fee
     */
    function updateRoyalties(address _collection, address _collectionOwner, uint _royalty) external onlyOwner {
        require(_royalty <= maxRoyaltyFee, "Marketplace: fee too high");
        CollectionCreatorFee memory _creatorFee = CollectionCreatorFee({fee: _royalty, owner: _collectionOwner});
        royalties[_collection] = _creatorFee;
        emit RoyaltiesUpdated(_collection, _royalty);
    }

    /**
     * Updates the marketplace base fee
     * @param _newFee new fee
     */
    function updateMarketplaceFee(uint _newFee) external onlyOwner {
        require(_newFee <= 1000);
        uint _oldFee = marketplaceFee;
        marketplaceFee = _newFee;
        emit MarketplaceFeeUpdated(_oldFee, _newFee);
    }

    /**
     * Updates the marketplace base fee receiver address
     * @param _newReceiver new receiver address
     */
    function updateFeeReceiver(address _newReceiver) external onlyOwner {
        feeReceiver = _newReceiver;
        emit MarketplaceFeeReceiverUpdated(_newReceiver);
    }

    receive() external payable {}
}
