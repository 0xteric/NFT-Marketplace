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

contract MarketplaceCore is Ownable, ReentrancyGuard {
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

    Payments public payments;

    uint public constant maxRoyaltyFee = 2000;
    uint public totalListings;
    uint public totalSales;
    uint public totalVolume;
    uint public nextListingId;
    address public marketplace;
    address public bidsModule;
    address[] public registeredCollections;

    mapping(address => Collection) public collections;
    mapping(address => mapping(uint => Listing)) public listings;

    event CollectionRegistered(address indexed collection, address indexed owner, uint royaltyFee);
    event ListingCreated(uint indexed id, address indexed collection, uint indexed tokenId, address seller, uint price);
    event ListingCancelled(uint indexed id, address indexed collection, uint indexed tokenId, address seller, uint price);
    event ListingSold(uint indexed id, address indexed collection, uint256 indexed tokenId, address seller, address buyer, uint256 price, uint256 marketplaceFee, uint256 royaltyFee);

    modifier onlyBidsOrMarketplace() {
        require(msg.sender == bidsModule || msg.sender == address(this) || msg.sender == marketplace, "Not allowed");
        _;
    }

    modifier onlyMarketplace() {
        require(msg.sender == marketplace || msg.sender == address(this), "Not allowed");
        _;
    }

    constructor(address payable _payments) Ownable(msg.sender) {
        payments = Payments(_payments);
    }

    /**
     * Bid address setter
     * @param _bidsModule contract address
     */

    function setBidsModule(address _bidsModule) external onlyOwner {
        bidsModule = _bidsModule;
    }

    /**
     * Marketplace address setter
     * @param _marketplace contract address
     */

    function setMarketplace(address _marketplace) external onlyOwner {
        marketplace = _marketplace;
    }

    /**
     * Payments contract setter
     * @param _payments contract address
     */

    function setPayments(address payable _payments) external onlyMarketplace {
        payments = Payments(_payments);
    }

    /**
     * Endpoint for Bids.sol contract and internal functions
     * @param _price order price
     * @param _royaltyReceiver collection royalty receiver address
     * @param _royaltyFee collection royalty fee value
     * @param _to receiver (seller) address
     * @param _col collection address (used to update collection stats)
     */
    function distributePaymentsFromBids(uint _price, address _royaltyReceiver, uint _royaltyFee, address _to, address _col) public onlyBidsOrMarketplace nonReentrant {
        _distributePayments(_price, _royaltyReceiver, _royaltyFee, _to, _col);
    }

    /**
     * Removes listings from the mapping, used as endpoint for Bids.sol contract
     * @param _collection collection address
     * @param _tokenId token id
     */

    function removeListing(address _collection, uint _tokenId) external onlyBidsOrMarketplace nonReentrant {
        Listing memory old = listings[_collection][_tokenId];
        require(old.price > 0, "Listing not exists");

        delete listings[_collection][_tokenId];
        totalListings -= 1;
        emit ListingCancelled(old.id, _collection, _tokenId, old.seller, old.price);
    }

    /**
     *
     * @param _price order price
     * @param _royaltyReceiver collection royalty receiver address
     * @param _royaltyFee collection royalty fee value
     * @param _to receiver (seller) address
     * @param _col collection address (used to update collection stats)
     */
    function _distributePayments(uint _price, address _royaltyReceiver, uint _royaltyFee, address _to, address _col) internal {
        Collection storage col = collections[_col];

        totalVolume += _price;
        totalSales += 1;
        col.totalSales += 1;
        col.totalVolume += _price;

        payments.distributePayments(_price, _royaltyReceiver, _royaltyFee, _to);
    }

    /**
     * Allows NFT collection owners to register their contracts in the marketplace core
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
     * Sets royalty fee value of the collection selected
     * @param _collection collection address
     * @param _receiver royalty fee receiver address
     * @param _fee royalty fee value
     */

    function setCollectionRoyalty(address _collection, address _receiver, uint _fee) external onlyMarketplace {
        Collection storage col = collections[_collection];
        require(_fee <= maxRoyaltyFee, "Royalty too high");
        require(col.exists, "Collection not registered");
        col.royaltyReceiver = _receiver;
        col.royaltyFee = _fee;
    }

    /**
     * Lists a sell order of a token
     * @param _collection token address
     * @param _tokenId token id
     * @param _price order price
     */
    function list(address _sender, address _collection, uint _tokenId, uint _price) public onlyMarketplace {
        require(collections[_collection].exists, "Not registered");
        require(_price > 0, "Price must be >0");
        require(IERC721(_collection).ownerOf(_tokenId) == _sender, "Not owner");
        require(IERC721(_collection).isApprovedForAll(_sender, address(this)), "Not approved");

        uint id = nextListingId++;
        if (listings[_collection][_tokenId].price > 0) {
            Listing memory old = listings[_collection][_tokenId];
            delete listings[_collection][_tokenId];
            totalListings -= 1;
            emit ListingCancelled(old.id, _collection, _tokenId, old.seller, old.price);
        }

        listings[_collection][_tokenId] = Listing(id, _sender, _price);
        totalListings += 1;
        emit ListingCreated(id, _collection, _tokenId, _sender, _price);
    }

    /**
     * Lists an array of sell orders
     * @param _collections tokens addresses array
     * @param _tokenIds tokens ids array
     * @param _prices orders price array
     */
    function listBatch(address _sender, address[] calldata _collections, uint[] calldata _tokenIds, uint[] calldata _prices) external onlyMarketplace {
        require(_collections.length == _tokenIds.length && _tokenIds.length == _prices.length, "Length mismatch");

        for (uint i = 0; i < _tokenIds.length; ) {
            list(_sender, _collections[i], _tokenIds[i], _prices[i]);
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
    function cancelList(address _sender, address _collection, uint _tokenId) public onlyMarketplace {
        Listing memory old = listings[_collection][_tokenId];

        require(old.price > 0, "Listing not exists");
        require(old.seller == _sender, "Not owner");

        delete listings[_collection][_tokenId];

        totalListings -= 1;
        emit ListingCancelled(old.id, _collection, _tokenId, _sender, old.price);
    }

    /**
     * Cancels an active listing
     * @param _collections tokens addresses array
     * @param _tokenIds tokens ids array
     */
    function cancelListBatch(address _sender, address[] calldata _collections, uint[] calldata _tokenIds) external onlyMarketplace {
        require(_collections.length == _tokenIds.length, "Length mismatch");

        for (uint i = 0; i < _tokenIds.length; ) {
            cancelList(_sender, _collections[i], _tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    function safeTransferItem(address _collection, address _from, address _to, uint _tokenId) public onlyMarketplace {
        IERC721(_collection).safeTransferFrom(_from, _to, _tokenId);
    }

    /**
     * Buys a token listed
     * @param _collection token address
     * @param _tokenId token id
     */
    function buy(address _sender, address _collection, uint _tokenId) external payable onlyMarketplace {
        require(msg.value == listings[_collection][_tokenId].price, "Insufficient value");
        _buy(_sender, _collection, _tokenId);
    }

    /**
     * Buys a token listed
     * @param _collection token address
     * @param _tokenId token id
     */
    function _buy(address _sender, address _collection, uint _tokenId) internal {
        Collection storage col = collections[_collection];

        require(col.exists, "Collection not registered");
        Listing memory _listing = listings[_collection][_tokenId];
        require(_listing.price > 0, "Listing not exists");
        require(IERC721(_collection).ownerOf(_tokenId) == _listing.seller, "Seller not owner");

        delete listings[_collection][_tokenId];
        (bool ok, ) = address(payments).call{value: _listing.price}("");
        require(ok, "Transfer failed!");
        safeTransferItem(_collection, _listing.seller, _sender, _tokenId);
        distributePaymentsFromBids(_listing.price, col.royaltyReceiver, col.royaltyFee, _listing.seller, _collection);

        totalListings -= 1;
        emit ListingSold(_listing.id, _collection, _tokenId, _listing.seller, _sender, _listing.price, payments.marketplaceFee(), collections[_collection].royaltyFee);
    }

    /**
     * Cancels an active token bid, returning the value to the owner
     * @param _collection token address
     * @param _tokenIds token ids array
     */
    function buyBatch(address _sender, address _collection, uint[] calldata _tokenIds) external payable onlyMarketplace {
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
            _buy(_sender, _collection, _tokenIds[i]);
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
}
