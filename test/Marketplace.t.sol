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
        (, , , uint _price) = marketplace.listings(address(mockNFT), 1);
        assertEq(_price, 0);

        marketplace.list(address(mockNFT), 1, 1 ether);
        (, , , uint __price) = marketplace.listings(address(mockNFT), 1);
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
        (, , , uint _price) = marketplace.listings(address(mockNFT), 1);
        assertEq(_price, 1 ether);

        marketplace.cancelList(address(mockNFT), 1);
        vm.stopPrank();

        (, , , uint __price) = marketplace.listings(address(mockNFT), 1);

        assertEq(__price, 0);
    }

    function testCancelListNotOwner() public {
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.list(address(mockNFT), 1, 1 ether);
        vm.stopPrank();
        (, , , uint _price) = marketplace.listings(address(mockNFT), 1);

        assertEq(_price, 1 ether);

        vm.prank(user2);
        vm.expectRevert("Not owner");
        marketplace.cancelList(address(mockNFT), 1);
    }

    function testBuy() public {
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.list(address(mockNFT), 1, 1 ether);
        (, , , uint _price) = marketplace.listings(address(mockNFT), 1);
        vm.stopPrank();

        assertEq(_price, 1 ether);
        assertEq(mockNFT.ownerOf(1), user1);

        vm.prank(user2);
        vm.deal(user2, 1 ether);
        marketplace.buy{value: 1 ether}(address(mockNFT), 1);
        (, , , uint __price) = marketplace.listings(address(mockNFT), 1);

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
        (, , , uint _price) = marketplace.listings(address(mockNFT), 1);
        vm.stopPrank();

        assertEq(_price, 1 ether);
        assertEq(mockNFT.ownerOf(1), user1);

        vm.prank(user2);
        vm.deal(user2, 1 ether);
        vm.expectRevert("Insufficient value");
        marketplace.buy{value: 0.5 ether}(address(mockNFT), 1);
    }

    function testBidCollection() public {
        vm.startPrank(user2);
        vm.deal(user2, 1 ether);

        marketplace.bidCollection{value: 0.5 ether}(address(mockNFT), 0.5 ether, 1);
        (, , , uint price) = marketplace.collectionBids(address(mockNFT), user2);

        assertEq(price, 0.5 ether);
        assertEq(user2.balance, 0.5 ether);
        assertEq(address(marketplace).balance, 0.5 ether);

        vm.stopPrank();
    }

    function testBidCollectionPriceZero() public {
        vm.startPrank(user2);
        vm.deal(user2, 1 ether);
        vm.expectRevert("Marketplace: price and quantity cannot be zero");
        marketplace.bidCollection{value: 0}(address(mockNFT), 0 ether, 0);
        vm.stopPrank();
    }

    function testBidNoCollection() public {
        vm.startPrank(user2);
        vm.deal(user2, 1 ether);
        vm.expectRevert("Marketplace: collection must exists");
        marketplace.bidCollection{value: 1 ether}(address(0), 1 ether, 1);
        vm.stopPrank();
    }

    function testBidNoSize() public {
        vm.startPrank(user2);
        vm.deal(user2, 1 ether);
        vm.expectRevert("Marketplace: add size to your bid");
        marketplace.bidCollection{value: 1 ether}(address(mockNFT), 1 ether, 2);
        vm.stopPrank();
    }

    function testBidAlreadyExist() public {
        vm.startPrank(user2);
        vm.deal(user2, 2 ether);
        marketplace.bidCollection{value: 1 ether}(address(mockNFT), 1 ether, 1);
        vm.expectRevert("Marketplace: collection already bidded");
        marketplace.bidCollection{value: 1 ether}(address(mockNFT), 1 ether, 1);
        vm.stopPrank();
    }

    function testCancelCollectionBid() public {
        vm.startPrank(user2);
        vm.deal(user2, 1 ether);
        marketplace.bidCollection{value: 1 ether}(address(mockNFT), 1 ether, 1);
        (, , , uint price) = marketplace.collectionBids(address(mockNFT), user2);

        assertEq(price, 1 ether);
        assertEq(user2.balance, 0 ether);
        assertEq(address(marketplace).balance, 1 ether);

        marketplace.cancelCollectionBid(address(mockNFT));
        (, , , uint priceAfter) = marketplace.collectionBids(address(mockNFT), user2);
        assertEq(priceAfter, 0);
        assertEq(user2.balance, 1 ether);
        assertEq(address(marketplace).balance, 0);
        vm.stopPrank();
    }

    function testCancelCollectionBidNotBidder() public {
        vm.startPrank(user2);
        vm.deal(user2, 1 ether);
        marketplace.bidCollection{value: 1 ether}(address(mockNFT), 1 ether, 1);
        (, , , uint price) = marketplace.collectionBids(address(mockNFT), user2);
        vm.stopPrank();

        assertEq(price, 1 ether);
        assertEq(user2.balance, 0 ether);
        assertEq(address(marketplace).balance, 1 ether);
        vm.startPrank(user1);

        vm.expectRevert("Marketplace: not bidder");
        marketplace.cancelCollectionBid(address(mockNFT));
        vm.stopPrank();
    }

    function testAcceptCollectionBid() public {
        vm.startPrank(user2);
        vm.deal(user2, 1 ether);
        marketplace.bidCollection{value: 1 ether}(address(mockNFT), 1 ether, 1);
        (, , , uint price) = marketplace.collectionBids(address(mockNFT), user2);
        vm.stopPrank();
    }
}
