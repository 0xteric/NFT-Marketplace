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
        marketplace = new Marketplace();
        mockNFT = new MockNFT();
        mockNFT.mint(user1, 1);
    }

    function testList() public {
        vm.startPrank(user1);
        marketplace.list(address(mockNFT), 1, 1 ether);
        (address collection, address seller, uint tokenId, uint price) = marketplace.listings(address(mockNFT), 1);
        vm.stopPrank();

        assertEq(collection, address(mockNFT));
        assertEq(seller, user1);
        assertEq(tokenId, 1);
        assertEq(price, 1 ether);
    }

    function testListPriceZero() public {
        vm.prank(user1);
        vm.expectRevert("Price must be greater");
        marketplace.list(address(mockNFT), 1, 0);
    }

    function testListNotOwner() public {
        vm.prank(user2);
        vm.expectRevert("Not owner");
        marketplace.list(address(mockNFT), 1, 1 ether);
    }

    function testCancelList() public {
        vm.startPrank(user1);
        marketplace.list(address(mockNFT), 1, 1 ether);
        (address _collection, address _seller, uint _tokenId, uint _price) = marketplace.listings(address(mockNFT), 1);

        assertEq(_collection, address(mockNFT));
        assertEq(_seller, user1);
        assertEq(_tokenId, 1);
        assertEq(_price, 1 ether);

        marketplace.cancelList(address(mockNFT), 1);
        vm.stopPrank();

        (address __collection, address __seller, uint __tokenId, uint __price) = marketplace.listings(address(mockNFT), 1);

        assertEq(__collection, address(0));
        assertEq(__seller, address(0));
        assertEq(__tokenId, 0);
        assertEq(__price, 0);
    }

    function testCancelListNotOwner() public {
        vm.prank(user1);
        marketplace.list(address(mockNFT), 1, 1 ether);
        (address _collection, address _seller, uint _tokenId, uint _price) = marketplace.listings(address(mockNFT), 1);

        assertEq(_collection, address(mockNFT));
        assertEq(_seller, user1);
        assertEq(_tokenId, 1);
        assertEq(_price, 1 ether);

        vm.prank(user2);
        vm.expectRevert("Not owner");
        marketplace.cancelList(address(mockNFT), 1);
    }

    function testBuy() public {
        vm.startPrank(user1);
        mockNFT.setApprovalForAll(address(marketplace), true);
        marketplace.list(address(mockNFT), 1, 1 ether);
        (address _collection, address _seller, uint _tokenId, uint _price) = marketplace.listings(address(mockNFT), 1);
        vm.stopPrank();

        assertEq(_collection, address(mockNFT));
        assertEq(_seller, user1);
        assertEq(_tokenId, 1);
        assertEq(_price, 1 ether);
        assertEq(mockNFT.ownerOf(1), user1);

        vm.prank(user2);
        vm.deal(user2, 1 ether);
        marketplace.buy{value: 1 ether}(address(mockNFT), 1);
        (address __collection, address __seller, uint __tokenId, uint __price) = marketplace.listings(address(mockNFT), 1);

        assertEq(__collection, address(0));
        assertEq(__seller, address(0));
        assertEq(__tokenId, 0);
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
        (address _collection, address _seller, uint _tokenId, uint _price) = marketplace.listings(address(mockNFT), 1);
        vm.stopPrank();

        assertEq(_collection, address(mockNFT));
        assertEq(_seller, user1);
        assertEq(_tokenId, 1);
        assertEq(_price, 1 ether);
        assertEq(mockNFT.ownerOf(1), user1);

        vm.prank(user2);
        vm.deal(user2, 1 ether);
        vm.expectRevert("Insufficient value");
        marketplace.buy{value: 0.5 ether}(address(mockNFT), 1);
    }
}
