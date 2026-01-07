// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./Payments.sol";

interface IERC721Ownable {
    function owner() external view returns (address);
}

contract MarketplaceCore is Ownable, ReentrancyGuard, Payments {
    struct Listing {
        uint id;
        address seller;
        uint price;
    }
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
    struct Collection {
        address collection;
        address royaltyReceiver;
        uint royaltyFee;
        uint totalVolume;
        uint totalSales;
        bool exists;
    }

    uint public constant maxRoyaltyFee = 2000;
    uint public totalListings;
    uint public totalSales;
    uint public totalVolume;
    uint public nextListingId;
    address[] public registeredCollections;

    mapping(address => Collection) public collections;
    mapping(address => mapping(uint => Listing)) public listings;
    mapping(address => mapping(address => CollectionBid)) public collectionBids;
    mapping(address => mapping(uint => mapping(address => TokenBid))) public tokenBids;

    event CollectionRegistered(address indexed collection, address indexed owner, uint royaltyFee);
    event ListingCreated(uint indexed id, address indexed collection, uint indexed tokenId, address seller, uint price);
    event ListingCancelled(uint indexed id, address indexed collection, uint indexed tokenId, address seller, uint price);
    event ListingSold(uint indexed id, address indexed collection, uint256 indexed tokenId, address seller, address buyer, uint256 price, uint256 marketplaceFee, uint256 royaltyFee);

    constructor(uint _initialFee) Payments(msg.sender, _initialFee) Ownable(msg.sender) {}

    /**
     *
     * @param _collection collection address
     * @param _royaltyFee fee paid by traders to collection owner
     */
    function registerCollection(address _collection, uint _royaltyFee) external {
        require(_collection != address(0), "Invalid collection");
        require(!collections[_collection].exists, "Already registered");
        require(_royaltyFee <= maxRoyaltyFee, "Royalty too high");
        require(IERC165(_collection).supportsInterface(type(IERC721).interfaceId));

        address collectionOwner;
        try IERC721Ownable(_collection).owner() returns (address _owner) {
            collectionOwner = _owner;
        } catch {
            revert("Collection must implement Ownable");
        }
        require(collectionOwner == msg.sender, "Not collection owner");

        collections[_collection] = Collection(_collection, msg.sender, _royaltyFee, 0, 0, true);
        registeredCollections.push(_collection);
        emit CollectionRegistered(_collection, msg.sender, _royaltyFee);
    }

    /**
     * Lists a sell order of a token
     * @param _collection token address
     * @param _tokenId token id
     * @param _price order price
     */
    function list(address _collection, uint _tokenId, uint _price) public {
        require(collections[_collection].exists, "Not registered");
        require(_price > 0, "Price must be >0");
        require(IERC721(_collection).ownerOf(_tokenId) == msg.sender, "Not owner");
        require(IERC721(_collection).isApprovedForAll(msg.sender, address(this)), "Not approved");

        uint id = nextListingId++;
        if (listings[_collection][_tokenId].price > 0) {
            Listing memory old = listings[_collection][_tokenId];
            delete listings[_collection][_tokenId];
            totalListings -= 1;
            emit ListingCancelled(old.id, _collection, _tokenId, msg.sender, old.price);
        }

        listings[_collection][_tokenId] = Listing(id, msg.sender, _price);
        totalListings += 1;
        emit ListingCreated(id, _collection, _tokenId, msg.sender, _price);
    }

    /**
     * Lists an array of sell orders
     * @param _collections tokens addresses array
     * @param _tokenIds tokens ids array
     * @param _prices orders price array
     */
    function listBatch(address[] calldata _collections, uint[] calldata _tokenIds, uint[] calldata _prices) external {
        require(_collections.length == _tokenIds.length && _tokenIds.length == _prices.length, "Length mismatch");

        for (uint i = 0; i < _tokenIds.length; ) {
            list(_collections[i], _tokenIds[i], _prices[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * Cancels an active listing
     * @param _collection token address
     * @param _tokenId token id
     */
    function cancelList(address _collection, uint _tokenId) public {
        require(listings[_collection][_tokenId].price > 0, "Listing not exists");
        require(listings[_collection][_tokenId].seller == msg.sender, "Not owner");

        Listing memory old = listings[_collection][_tokenId];
        delete listings[_collection][_tokenId];

        totalListings -= 1;
        emit ListingCancelled(old.id, _collection, _tokenId, msg.sender, old.price);
    }

    /**
     * Cancels an active listing
     * @param _collections tokens addresses array
     * @param _tokenIds tokens ids array
     */
    function cancelListBatch(address[] calldata _collections, uint[] calldata _tokenIds) external {
        require(_collections.length == _tokenIds.length, "Length mismatch");

        for (uint i = 0; i < _tokenIds.length; ) {
            cancelList(_collections[i], _tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * Buys a token listed
     * @param _collection token address
     * @param _tokenId token id
     */
    function buy(address _collection, uint _tokenId) external payable nonReentrant {
        require(msg.value == listings[_collection][_tokenId].price, "Insufficient value");
        _buy(_collection, _tokenId);
    }

    /**
     * Buys a token listed
     * @param _collection token address
     * @param _tokenId token id
     */
    function _buy(address _collection, uint _tokenId) internal {
        Collection storage col = collections[_collection];

        require(col.exists, "Collection not registered");
        Listing memory _listing = listings[_collection][_tokenId];
        require(_listing.price > 0, "Listing not exists");

        delete listings[_collection][_tokenId];

        _distributePayments(_listing.price, col.royaltyReceiver, col.royaltyFee, _listing.seller);

        IERC721(_collection).safeTransferFrom(_listing.seller, msg.sender, _tokenId);

        totalSales += 1;
        col.totalSales += 1;
        col.totalVolume += _listing.price;
        totalListings -= 1;
        emit ListingSold(_listing.id, _collection, _tokenId, _listing.seller, msg.sender, _listing.price, marketplaceFee, collections[_collection].royaltyFee);
    }

    /**
     * Cancels an active token bid, returning the value to the owner
     * @param _collection token address
     * @param _tokenIds token ids array
     */
    function buyBatch(address _collection, uint[] calldata _tokenIds) external payable nonReentrant {
        uint _totalPrice;

        for (uint i = 0; i < _tokenIds.length; ) {
            uint price = listings[_collection][_tokenIds[i]].price;
            require(price > 0, "Listing not exists");
            _totalPrice += price;

            unchecked {
                ++i;
            }
        }
        require(msg.value == _totalPrice, "Marketplace: Incorrect ETH");

        for (uint i = 0; i < _tokenIds.length; ) {
            _buy(_collection, _tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }
}
