// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MarketplaceCore.sol";
import "./Bids.sol";
import "./Payments.sol";

/**
 * @title Marketplace
 * @dev Modular contract combining MarketplaceCore, Bids y Payments
 */
contract Marketplace is Bids {
    bool requireOwnable;

    constructor(uint _initialFee) Bids(_initialFee) {}

    function updateMarketplaceFee(uint _newFee) external onlyOwner {
        require(_newFee <= maxRoyaltyFee, "Fee too high");
        uint oldFee = marketplaceFee;
        super.updateMarketplaceFee(_newFee);
        emit MarketplaceFeeUpdated(oldFee, _newFee);
    }

    function updateFeeReceiver(address _newReceiver) external onlyOwner {
        require(_newReceiver != address(0), "Invalid receiver");
        super.updateFeeReceiver(_newReceiver);
        emit MarketplaceFeeReceiverUpdated(_newReceiver);
    }

    function switchRequireOwnable() external onlyOwner {
        requireOwnable = !requireOwnable;
    }

    function updateCollectionRoyalties(address _collection, uint _newRoyalty) external {
        Collection storage col = collections[_collection];
        require(col.exists, "Collection not registered");
        if (requireOwnable) {
            require(IERC721Ownable(_collection).owner() == msg.sender, "Not collection owner");
        }
        require(_newRoyalty <= maxRoyaltyFee, "Royalty too high");

        col.royaltyFee = _newRoyalty;
        emit RoyaltiesUpdated(_collection, _newRoyalty);
    }

    receive() external payable {}

    fallback() external payable {}
}
