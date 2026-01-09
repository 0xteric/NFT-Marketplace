// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Payments.sol";
import "../src/MarketplaceCore.sol";
import "../src/Bids.sol";
import "../src/Marketplace.sol";
import "./MockNFT.t.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MarketplaceTest is Test {
    Payments payments;
    MarketplaceCore core;
    Bids bids;
    Marketplace marketplace;

    MockNFT nft;
    address alice = vm.addr(2);
    address bob = vm.addr(1);
    address feeReceiver = vm.addr(3);

    function setUp() public {
        // Deploy contracts
        vm.startPrank(alice);

        payments = new Payments(500); // 5% fee
        core = new MarketplaceCore(payable(address(payments)));
        bids = new Bids(payable(address(core)));
        marketplace = new Marketplace(payable(address(bids)), payable(address(core)), payable(address(payments)));
        nft = new MockNFT();

        // Setup permissions
        payments.setCore(address(core));
        payments.setBids(address(bids));
        core.setMarketplace(address(marketplace));
        core.setBidsModule(address(bids));
        vm.stopPrank();
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(feeReceiver, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        COLLECTION REGISTRATION
    //////////////////////////////////////////////////////////////*/

    function testRegisterCollection() public {
        nft.mint(alice, 1);
        vm.startPrank(alice);

        nft.setApprovalForAll(address(marketplace), true);
        core.registerCollection(address(nft), 500); // 5% royalty
        vm.stopPrank();

        (address col, address rr, uint rf, , , bool exists) = core.collections(address(nft));
        assertEq(rr, alice);
        assertEq(rf, 500);
        assertTrue(exists);
    }

    /*//////////////////////////////////////////////////////////////
                          LIST & BUY TESTS
    //////////////////////////////////////////////////////////////*/

    function testListAndBuy() public {
        nft.mint(alice, 1);
        vm.startPrank(alice);
        nft.setApprovalForAll(address(core), true);
        core.registerCollection(address(nft), 500);

        marketplace.list(address(nft), 1, 1 ether);
        vm.stopPrank();

        // Bob buys NFT
        vm.startPrank(bob);
        vm.deal(bob, 2 ether);
        marketplace.buy{value: 1 ether}(address(nft), 1);
        vm.stopPrank();

        assertEq(nft.ownerOf(1), bob);
    }

    function testBuyInsufficientValueReverts() public {
        nft.mint(alice, 1);
        vm.startPrank(alice);
        nft.setApprovalForAll(address(marketplace), true);
        core.registerCollection(address(nft), 500);

        marketplace.list(address(nft), 1, 1 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.deal(bob, 2 ether);
        vm.expectRevert(bytes("Insufficient value"));
        marketplace.buy{value: 0.5 ether}(address(nft), 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          PAYMENTS TESTS
    //////////////////////////////////////////////////////////////*/

    function testDistributePayments() public {
        // Simulate core calling payments
        payments.setCore(address(core));
        uint price = 1 ether;
        uint royaltyFee = 500; // 5%
        vm.deal(address(payments), price);
        payments.distributePayments(price, bob, royaltyFee, alice);

        assertEq(alice.balance, 950_000_000_000_000_000); // 0.95 ETH minus 5% marketplace fee
        assertEq(bob.balance, 50_000_000_000_000_000); // royalty 0.05 ETH
    }

    function testRefund() public {
        vm.deal(address(payments), 1 ether);
        payments.setCore(address(core));
        payments.setBids(address(bids));

        uint refundAmount = 0.5 ether;
        payments.refund(alice, refundAmount);

        assertEq(alice.balance, refundAmount);
    }

    /*//////////////////////////////////////////////////////////////
                          REQUIRE FAILURE TEST
    //////////////////////////////////////////////////////////////*/

    function testRequireFailOnNonCore() public {
        vm.startPrank(bob);
        vm.expectRevert(bytes("Not core"));
        payments.distributePayments(1 ether, bob, 500, alice);
        vm.stopPrank();
    }
}
