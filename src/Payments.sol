// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Payments is Ownable, ReentrancyGuard {
    uint public constant basisPoints = 10_000;
    address public feeReceiver;
    uint public marketplaceFee;
    address public core;
    address public bids;

    modifier onlyCore() {
        require(msg.sender == core, "Not core");
        _;
    }

    modifier onlyKnown() {
        require(msg.sender == core || msg.sender == bids, "Not core");
        _;
    }

    constructor(uint _marketplaceFee) Ownable(msg.sender) {
        feeReceiver = msg.sender;
        marketplaceFee = _marketplaceFee;
    }

    /**
     * Sets MarketplaceCore contract address
     * @param _core new core contract address
     */

    function setCore(address _core) external onlyOwner {
        core = _core;
    }

    /**
     * Sets MarketplaceCore contract address
     * @param _bids new core contract address
     */

    function setBids(address _bids) external onlyOwner {
        bids = _bids;
    }

    /**
     * Processes all ETH payments relative to trades
     * @param _price order price
     * @param _royaltyReceiver collection fee receiver
     * @param _royaltyFee collection fee
     * @param _to receiver (seller) address
     */

    function distributePayments(uint _price, address _royaltyReceiver, uint _royaltyFee, address _to) external payable onlyCore {
        uint fee = (_price * marketplaceFee) / basisPoints;
        uint royalty = (_price * _royaltyFee) / basisPoints;
        uint payment = _price - fee - royalty;

        (bool ok1, ) = feeReceiver.call{value: fee}("");
        require(ok1, "Fee transfer failed");
        (bool ok2, ) = _to.call{value: payment}("");
        require(ok2, "Payment transfer failed");

        if (royalty > 0) {
            (bool ok3, ) = _royaltyReceiver.call{value: royalty}("");
            require(ok3, "Royalties transfer failed");
        }
    }

    function refund(address _user, uint _amount) external nonReentrant onlyKnown returns (bool) {
        (bool ok, ) = _user.call{value: _amount}("");
        require(ok, "Refund failed!");

        return true;
    }

    /**
     * Updates marketplace base fee value
     * @param _newFee new fee in basis points (10_000)
     */
    function updateMarketplaceFee(uint _newFee) external onlyOwner {
        require(_newFee <= 2000, "Fee too high");
        marketplaceFee = _newFee;
    }

    /**
     * Updates marketplace base fee receiver address
     * @param _newReceiver new receiver address
     */
    function updateFeeReceiver(address _newReceiver) external onlyOwner {
        require(_newReceiver != address(0), "Invalid receiver");

        feeReceiver = _newReceiver;
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
