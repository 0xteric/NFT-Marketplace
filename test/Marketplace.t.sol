// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "../src/Marketplace.sol";

contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MOCK") {}

    function mint(address _to, uint _id) external {
        _mint(_to, _id);
    }
}

contract MarketplaceTest is Test {
    Marketplace marketplace;
    MockNFT mockNFT;

    address deployer = vm.addr(1);
    address user1 = vm.addr(2);
    address user2 = vm.addr(3);

    function setUp() public {
        vm.prank(deployer);
        marketplace = new Marketplace(200);
        mockNFT = new MockNFT();
        mockNFT.mint(user1, 1);
    }

    function testList() public {
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);
        (, , uint _price) = marketplace.listings(address(mockNFT), 1);
        assertEq(_price, 0);

        marketplace.list(address(mockNFT), 1, 1 ether);
        (, , uint __price) = marketplace.listings(address(mockNFT), 1);
        vm.stopPrank();

        assertEq(_price == 0, __price == 1 ether);
    }

    function testListPriceZero() public {
        vm.prank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);
        vm.expectRevert("Price must be greater");
        marketplace.list(address(mockNFT), 1, 0);
    }

    function testListNotOwner() public {
        vm.startPrank(user2);
        mockNFT.setApprovalForAll(address(marketplace), true);
        vm.expectRevert("Not owner");
        marketplace.list(address(mockNFT), 1, 1 ether);
        vm.stopPrank();
    }

    function testCancelList() public {
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.list(address(mockNFT), 1, 1 ether);
        (, , uint _price) = marketplace.listings(address(mockNFT), 1);
        assertEq(_price, 1 ether);

        marketplace.cancelList(address(mockNFT), 1);
        vm.stopPrank();

        (, , uint __price) = marketplace.listings(address(mockNFT), 1);

        assertEq(__price, 0);
    }

    function testCancelListNotOwner() public {
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.list(address(mockNFT), 1, 1 ether);
        vm.stopPrank();
        (, , uint _price) = marketplace.listings(address(mockNFT), 1);

        assertEq(_price, 1 ether);

        vm.prank(user2);
        vm.expectRevert("Not owner");
        marketplace.cancelList(address(mockNFT), 1);
    }

    function testBuy() public {
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.list(address(mockNFT), 1, 1 ether);
        (, , uint _price) = marketplace.listings(address(mockNFT), 1);
        vm.stopPrank();

        assertEq(_price, 1 ether);
        assertEq(mockNFT.ownerOf(1), user1);

        vm.prank(user2);
        vm.deal(user2, 1 ether);
        marketplace.buy{value: 1 ether}(address(mockNFT), 1);
        (, , uint __price) = marketplace.listings(address(mockNFT), 1);

        assertEq(__price, 0);
        assertEq(mockNFT.ownerOf(1), user2);
    }

    function testBuyNotExists() public {
        vm.startPrank(user1);
        vm.deal(user1, 1 ether);
        vm.expectRevert("Listing not exists");
        marketplace.buy{value: 1 ether}(address(mockNFT), 1);
    }

    function testBuyInsufficientValue() public {
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.list(address(mockNFT), 1, 1 ether);
        (, , uint _price) = marketplace.listings(address(mockNFT), 1);
        vm.stopPrank();

        assertEq(_price, 1 ether);
        assertEq(mockNFT.ownerOf(1), user1);

        vm.prank(user2);
        vm.deal(user2, 1 ether);
        vm.expectRevert("Insufficient value");
        marketplace.buy{value: 0.5 ether}(address(mockNFT), 1);
    }

    function testBidCollection() public {
        uint bidPrice = 0.5 ether;
        vm.startPrank(user2);
        vm.deal(user2, 1 ether);

        marketplace.bidCollection{value: bidPrice}(address(mockNFT), bidPrice, 1);
        (, , uint price) = marketplace.collectionBids(address(mockNFT), user2);

        assertEq(price, bidPrice);
        assertEq(user2.balance, bidPrice);
        assertEq(address(marketplace).balance, bidPrice);

        vm.stopPrank();
    }

    function testBidCollectionPriceZero() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        vm.expectRevert("Marketplace: price and quantity cannot be zero");
        marketplace.bidCollection{value: 0}(address(mockNFT), 0 ether, 0);
        vm.stopPrank();
    }

    function testBidNoCollection() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        vm.expectRevert("Marketplace: collection must exists");
        marketplace.bidCollection{value: bidPrice}(address(0), bidPrice, 1);
        vm.stopPrank();
    }

    function testBidNoSize() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        vm.expectRevert("Marketplace: add size to your bid");
        marketplace.bidCollection{value: bidPrice}(address(mockNFT), bidPrice, 2);
        vm.stopPrank();
    }

    function testBidAlreadyExist() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, 2 ether);
        marketplace.bidCollection{value: bidPrice}(address(mockNFT), bidPrice, 1);
        vm.expectRevert("Marketplace: collection already bidded");
        marketplace.bidCollection{value: bidPrice}(address(mockNFT), bidPrice, 1);
        vm.stopPrank();
    }

    function testCancelCollectionBid() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        marketplace.bidCollection{value: bidPrice}(address(mockNFT), bidPrice, 1);
        (, , uint price) = marketplace.collectionBids(address(mockNFT), user2);

        assertEq(price, bidPrice);
        assertEq(user2.balance, 0);
        assertEq(address(marketplace).balance, bidPrice);

        marketplace.cancelCollectionBid(address(mockNFT));
        (, , uint priceAfter) = marketplace.collectionBids(address(mockNFT), user2);
        assertEq(priceAfter, 0);
        assertEq(user2.balance, bidPrice);
        assertEq(address(marketplace).balance, 0);
        vm.stopPrank();
    }

    function testCancelCollectionBidNotBidder() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        marketplace.bidCollection{value: bidPrice}(address(mockNFT), bidPrice, 1);
        (, , uint price) = marketplace.collectionBids(address(mockNFT), user2);
        vm.stopPrank();

        assertEq(price, bidPrice);
        assertEq(user2.balance, 0);
        assertEq(address(marketplace).balance, bidPrice);
        vm.startPrank(user1);

        vm.expectRevert("Marketplace: not bidder");
        marketplace.cancelCollectionBid(address(mockNFT));
        vm.stopPrank();
    }

    function testAcceptCollectionBid() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        marketplace.bidCollection{value: bidPrice}(address(mockNFT), bidPrice, 1);
        vm.stopPrank();

        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        marketplace.acceptCollectionBid(address(mockNFT), user2, tokenIds);

        uint sellerPayment = bidPrice - (bidPrice * marketplace.marketplaceFee()) / marketplace.basisPoints();
        assertEq(mockNFT.ownerOf(1), user2);
        assertEq(user1.balance, sellerPayment);
        vm.stopPrank();
    }

    function testAcceptCollectionBidExceedsQuantity() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        marketplace.bidCollection{value: bidPrice}(address(mockNFT), bidPrice, 1);
        vm.stopPrank();

        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        vm.expectRevert("Marketplace: quantity exceeds bid");
        marketplace.acceptCollectionBid(address(mockNFT), user2, tokenIds);
        vm.stopPrank();
    }

    function testAcceptCollectionBidNotBalance() public {
        uint bidPrice = 1 ether;
        uint bidQuantity = 2;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice * bidQuantity);
        marketplace.bidCollection{value: bidPrice * bidQuantity}(address(mockNFT), bidPrice, bidQuantity);
        vm.stopPrank();

        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        vm.expectRevert("Marketplace: not enough balance");
        marketplace.acceptCollectionBid(address(mockNFT), user2, tokenIds);
        vm.stopPrank();
    }

    function testAcceptCollectionBidNotApproved() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        marketplace.bidCollection{value: bidPrice}(address(mockNFT), bidPrice, 1);
        vm.stopPrank();

        vm.startPrank(user1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.expectRevert("Marketplace: collection not approved");
        marketplace.acceptCollectionBid(address(mockNFT), user2, tokenIds);
        vm.stopPrank();
    }

    function testBidToken() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        assertEq(user2.balance, bidPrice);
        marketplace.bidToken{value: bidPrice}(address(mockNFT), 1, bidPrice);
        (, , uint price) = marketplace.tokenBids(address(mockNFT), 1, user2);
        assertEq(user2.balance, 0);
        assertEq(price, bidPrice);
        vm.stopPrank();
    }

    function testBidTokenNotExists() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        assertEq(user2.balance, bidPrice);
        vm.expectRevert("Marketplace: collection and price should exist");
        marketplace.bidToken{value: bidPrice}(address(0), 1, bidPrice);
        vm.stopPrank();
    }

    function testBidTokenNotSize() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        assertEq(user2.balance, bidPrice);
        vm.expectRevert("Marketplace: add size to bid");
        marketplace.bidToken(address(mockNFT), 1, bidPrice);
        vm.stopPrank();
    }

    function testAcceptTokenBid() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        assertEq(user2.balance, bidPrice);
        marketplace.bidToken{value: bidPrice}(address(mockNFT), 1, bidPrice);
        vm.stopPrank();

        assertEq(mockNFT.ownerOf(1), user1);
        assertEq(address(marketplace).balance, bidPrice);

        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.acceptTokenBid(address(mockNFT), user2, 1);

        assertEq(mockNFT.ownerOf(1), user2);
        assertEq(user1.balance, bidPrice - ((bidPrice * marketplace.marketplaceFee()) / marketplace.basisPoints()));
        vm.stopPrank();
    }

    function testAcceptTokenBidNotExists() public {
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);
        vm.expectRevert("Marketplace: bid doesn't exists");
        marketplace.acceptTokenBid(address(mockNFT), user2, 1);
        vm.stopPrank();
    }

    function testAcceptTokenBidNotOwner() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        assertEq(user2.balance, bidPrice);
        marketplace.bidToken{value: bidPrice}(address(mockNFT), 1, bidPrice);
        vm.stopPrank();

        assertEq(mockNFT.ownerOf(1), user1);
        assertEq(address(marketplace).balance, bidPrice);

        vm.startPrank(deployer);
        mockNFT.setApprovalForAll(address(marketplace), true);
        vm.expectRevert("Marketplace: Not owner");
        marketplace.acceptTokenBid(address(mockNFT), user2, 1);
        vm.stopPrank();
    }

    function testAcceptTokenBidNotApproved() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        assertEq(user2.balance, bidPrice);
        marketplace.bidToken{value: bidPrice}(address(mockNFT), 1, bidPrice);
        vm.stopPrank();

        assertEq(mockNFT.ownerOf(1), user1);
        assertEq(address(marketplace).balance, bidPrice);

        vm.startPrank(user1);
        vm.expectRevert("Marketplace: collection not approved");
        marketplace.acceptTokenBid(address(mockNFT), user2, 1);
        vm.stopPrank();
    }

    function testCancelTokenBid() public {
        uint bidPrice = 1 ether;
        vm.startPrank(user2);
        vm.deal(user2, bidPrice);
        assertEq(user2.balance, bidPrice);
        marketplace.bidToken{value: bidPrice}(address(mockNFT), 1, bidPrice);
        (, , uint price) = marketplace.tokenBids(address(mockNFT), 1, user2);
        assertEq(user2.balance, 0);
        assertEq(price, bidPrice);

        marketplace.cancelTokenBid(address(mockNFT), 1);

        (, , uint priceAfter) = marketplace.tokenBids(address(mockNFT), 1, user2);
        assertEq(user2.balance, bidPrice);
        assertEq(priceAfter, 0);
        vm.stopPrank();
    }

    function testCancelTokenBidNotExists() public {
        vm.startPrank(user2);

        vm.expectRevert("Marketplace: bid not exists");
        marketplace.cancelTokenBid(address(mockNFT), 1);
        vm.stopPrank();
    }

    function testUpdateRoyalties() public {
        vm.startPrank(deployer);

        (, , uint fee, , , ) = marketplace.collections(address(mockNFT));
        assertEq(fee, 0);

        marketplace.updateCollectionRoyalties(address(mockNFT), 500);
        (, , uint feeAfter, , , ) = marketplace.collections(address(mockNFT));

        assertEq(feeAfter, 500);
        vm.stopPrank();
    }

    function testUpdateRoyaltiesFeeTooHigh() public {
        vm.startPrank(deployer);
        vm.expectRevert("Marketplace: fee too high");
        marketplace.updateCollectionRoyalties(address(mockNFT), 3000);
        vm.stopPrank();
    }

    function testUpdateMarketplaceFee() public {
        vm.startPrank(deployer);
        uint feeBefore = marketplace.marketplaceFee();
        marketplace.updateMarketplaceFee(1000);
        uint feeAfter = marketplace.marketplaceFee();
        assertTrue(feeBefore != feeAfter);
        assertTrue(1000 == feeAfter);
        vm.stopPrank();
    }

    function testUpdateFeeReceiver() public {
        vm.startPrank(deployer);
        address receiverBefore = marketplace.feeReceiver();
        marketplace.updateFeeReceiver(user1);
        address receiverAfter = marketplace.feeReceiver();
        assertTrue(receiverBefore != receiverAfter);
        assertEq(receiverAfter, user1);
        vm.stopPrank();
    }
}
