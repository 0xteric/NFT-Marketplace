// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MarketplaceCore.sol";
import "./Bids.sol";
import "./Payments.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Marketplace
 * @dev Modular contract combining MarketplaceCore, Bids y Payments
 */
contract Marketplace is Ownable, ReentrancyGuard {
    Bids public bids;
    MarketplaceCore public core;
    Payments public payments;

    bool requireOwnable;

    event MarketplaceFeeUpdated(uint oldFee, uint newFee);
    event MarketplaceFeeReceiverUpdated(address newReceiver);
    event RoyaltiesUpdated(address collection, uint newRoyalty);

    constructor(address payable _bids, address _core, address payable _payments) Ownable(msg.sender) {
        bids = Bids(_bids);
        core = MarketplaceCore(_core);
        payments = Payments(_payments);
    }

    /*  CORE  */

    /**
     * Lists a token for sale
     * @param _collection NFT collection address
     * @param _tokenId token ID
     * @param _price listing price
     */
    function list(address _collection, uint _tokenId, uint _price) external {
        core.list(msg.sender, _collection, _tokenId, _price);
    }

    /**
     * Lists multiple tokens for sale
     * @param _collections NFT collection addresses
     * @param _tokenIds token IDs
     * @param _prices listing prices
     */
    function listBatch(address[] calldata _collections, uint[] calldata _tokenIds, uint[] calldata _prices) external {
        core.listBatch(msg.sender, _collections, _tokenIds, _prices);
    }

    /**
     * Cancels an active listing
     * @param _collection NFT collection address
     * @param _tokenId token ID
     */
    function cancelList(address _collection, uint _tokenId) external {
        core.cancelList(msg.sender, _collection, _tokenId);
    }

    /**
     * Cancels multiple active listings
     * @param _collections NFT collection addresses
     * @param _tokenIds token IDs
     */
    function cancelListBatch(address[] calldata _collections, uint[] calldata _tokenIds) external {
        core.cancelListBatch(msg.sender, _collections, _tokenIds);
    }

    /**
     * Buys a listed token
     * @param _collection NFT collection address
     * @param _tokenId token ID
     */
    function buy(address _collection, uint _tokenId) external payable {
        try core.buy{value: msg.value}(msg.sender, _collection, _tokenId) {} catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("MarketplaceCore: unknown error");
        }
    }

    /**
     * Buys multiple listed tokens from the same collection
     * @param _collection NFT collection address
     * @param _tokenIds token IDs
     */
    function buyBatch(address _collection, uint[] calldata _tokenIds) external payable {
        try core.buyBatch{value: msg.value}(msg.sender, _collection, _tokenIds) {} catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("MarketplaceCore: unknown error");
        }
    }

    /*  BIDS  */

    /**
     * Creates a bid for any token of a collection
     * @param _collection NFT collection address
     * @param _price price per token
     * @param _quantity amount of tokens to buy
     */
    function bidCollection(address _collection, uint _price, uint _quantity) external payable {
        require(msg.value == _price * _quantity, "Incorrect value");
        bids.bidCollection(_collection, _price, _quantity);
        (bool ok, ) = address(payments).call{value: msg.value}("");
        require(ok, "Transfer failed");
    }

    /**
     * Cancels an active collection bid and refunds ETH
     * @param _collection NFT collection address
     */
    function cancelCollectionBid(address _collection) external {
        bids.cancelCollectionBid(_collection);
    }

    /**
     * Accepts a collection bid selling multiple tokens
     * @param _collection NFT collection address
     * @param _bidder bidder address
     * @param _tokenIds list of token IDs to sell
     */
    function acceptCollectionBid(address _collection, address _bidder, uint[] calldata _tokenIds) external nonReentrant {
        (, , uint price) = bids.collectionBids(_collection, _bidder);
        (, address rr, uint rf, , , ) = core.collections(_collection);

        bids.acceptCollectionBid(msg.sender, _collection, _bidder, _tokenIds);

        uint pricePerToken = price;
        uint totalPrice = pricePerToken * _tokenIds.length;

        for (uint i = 0; i < _tokenIds.length; ) {
            core.safeTransferItem(_collection, msg.sender, _bidder, _tokenIds[i]);
            unchecked {
                ++i;
            }
        }

        core.distributePaymentsFromBids(totalPrice, rr, rf, msg.sender, _collection);
    }

    /**
     * Creates a bid for a specific token
     * @param _collection NFT collection address
     * @param _tokenId token ID
     * @param _price bid price
     */
    function bidToken(address _collection, uint _tokenId, uint _price) external payable {
        require(msg.value == _price, "Incorrect value");
        bids.bidToken(msg.sender, _collection, _tokenId, _price);
        (bool ok, ) = address(payments).call{value: msg.value}("");
        require(ok, "Transfer failed");
    }

    /**
     * Creates multiple bids for specific tokens
     * @param _collection NFT collection address
     * @param _tokenIds list of token IDs
     * @param _prices list of bid prices
     */
    function bidTokenBatch(address _collection, uint[] calldata _tokenIds, uint[] calldata _prices) external payable {
        require(_tokenIds.length == _prices.length, "Length mismatch");

        uint totalPrice;
        for (uint i = 0; i < _prices.length; ) {
            totalPrice += _prices[i];
            unchecked {
                ++i;
            }
        }
        require(msg.value == totalPrice, "Incorrect value");

        bids.bidTokenBatch(msg.sender, _collection, _tokenIds, _prices);
        (bool ok, ) = address(payments).call{value: msg.value}("");
        require(ok, "Transfer failed");
    }

    /**
     * Accepts a bid for a specific token
     * @param _collection NFT collection address
     * @param _bidder bidder address
     * @param _tokenId token ID
     */
    function acceptTokenBid(address _collection, address _bidder, uint _tokenId) external nonReentrant {
        (, , uint price) = bids.tokenBids(_collection, _tokenId, _bidder);
        (, address rr, uint rf, , , bool exists) = core.collections(_collection);
        require(exists, "Collection not registered");

        bids.acceptTokenBid(msg.sender, _collection, _bidder, _tokenId);

        core.safeTransferItem(_collection, msg.sender, _bidder, _tokenId);
        core.distributePaymentsFromBids(price, rr, rf, msg.sender, _collection);
    }

    /**
     * Cancels an active token bid and refunds ETH
     * @param _collection NFT collection address
     * @param _tokenId token ID
     */
    function cancelTokenBid(address _collection, uint _tokenId) external {
        bids.cancelTokenBid(msg.sender, _collection, _tokenId);
    }

    /**
     * Cancels multiple active token bids
     * @param _collections NFT collections
     * @param _tokenIds token IDs
     */
    function cancelTokenBidBatch(address[] calldata _collections, uint[] calldata _tokenIds) external {
        bids.cancelTokenBidBatch(msg.sender, _collections, _tokenIds);
    }

    /**
     * Updates collection royalty fee value and receiver
     * @param _collection address
     * @param _newReceiver receiver
     * @param _newRoyalty fee value
     */
    function updateCollectionRoyalties(address _collection, address _newReceiver, uint _newRoyalty) external {
        if (requireOwnable) {
            require(IERC721Ownable(_collection).owner() == msg.sender, "Not collection owner");
        } else {
            require(owner() == msg.sender, "Not marketplace owner");
        }
        core.setCollectionRoyalty(_collection, _newReceiver, _newRoyalty);
        emit RoyaltiesUpdated(_collection, _newRoyalty);
    }

    /*  ADMIN  */

    /**
     * Updates marketplace base fee value
     * @param _newFee fee value
     */

    function updateMarketplaceFee(uint _newFee) external onlyOwner {
        require(_newFee <= core.maxRoyaltyFee(), "Fee too high");
        uint oldFee = payments.marketplaceFee();
        payments.updateMarketplaceFee(_newFee);
        emit MarketplaceFeeUpdated(oldFee, _newFee);
    }

    /**
     * Updates marketplace base fee receiver address
     * @param _newReceiver address
     */
    function updateFeeReceiver(address _newReceiver) external onlyOwner {
        require(_newReceiver != address(0), "Invalid receiver");
        payments.updateFeeReceiver(_newReceiver);
        emit MarketplaceFeeReceiverUpdated(_newReceiver);
    }

    /**
     * Switch restriction between marketplace owner and collection owner to update royalties
     */
    function switchRequireOwnable() external onlyOwner {
        requireOwnable = !requireOwnable;
    }

    /**
     * Updates references to MarketplaceCore smart contract
     * @param _newAddress address
     */
    function setPayments(address payable _newAddress) external onlyOwner {
        payments = Payments(_newAddress);
        core.setPayments(_newAddress);
    }

    /**
     * Updates references to MarketplaceCore smart contract
     * @param _newAddress address
     */
    function setCore(address _newAddress) external onlyOwner {
        core = MarketplaceCore(_newAddress);
        payments.setCore(_newAddress);
        bids.setCore(_newAddress);
    }

    /**
     * Updates references to Bid smart contract
     * @param _newAddress address
     */
    function setBids(address payable _newAddress) external onlyOwner {
        bids = Bids(_newAddress);
        core.setBidsModule(_newAddress);
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
