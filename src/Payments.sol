// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Payments {
    uint public constant basisPoints = 10000;
    address public feeReceiver;
    uint public marketplaceFee;

    constructor(address _feeReceiver, uint _marketplaceFee) {
        feeReceiver = _feeReceiver;
        marketplaceFee = _marketplaceFee;
    }

    function _distributePayments(uint _price, address _royaltyReceiver, uint _royaltyFee, address _to) internal {
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

    function updateMarketplaceFee(uint _newFee) internal {
        marketplaceFee = _newFee;
    }

    function updateFeeReceiver(address _newReceiver) internal {
        feeReceiver = _newReceiver;
    }
}
