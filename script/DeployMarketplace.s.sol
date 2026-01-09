// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/Payments.sol";
import "../src/Bids.sol";
import "../src/MarketplaceCore.sol";
import "../src/Marketplace.sol";

contract DeployMarketplace is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PK");

        vm.startBroadcast(deployerKey);

        uint256 initialMarketplaceFee = 250;

        Payments payments = new Payments(initialMarketplaceFee);
        console2.log("Payments deployed at:", payable(payments));

        MarketplaceCore core = new MarketplaceCore(payable(payments));
        console2.log("Core deployed at:", address(core));

        payments.setCore(address(core));

        Bids bids = new Bids(address(core));
        console2.log("Bids deployed at:", payable(bids));

        core.setBidsModule(address(bids));
        payments.setBids(address(bids));

        Marketplace marketplace = new Marketplace(payable(bids), address(core), payable(payments));
        console2.log("Marketplace deployed at:", payable(marketplace));

        core.setMarketplace(address(marketplace));

        vm.stopBroadcast();
    }
}
