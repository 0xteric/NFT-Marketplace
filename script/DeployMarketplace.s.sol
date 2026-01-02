// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/Marketplace.sol";

contract DeployMarketplace is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PK");

        uint256 initialMarketplaceFee = 250;

        vm.startBroadcast(deployerPrivateKey);

        Marketplace marketplace = new Marketplace(initialMarketplaceFee);

        vm.stopBroadcast();

        console2.log("Marketplace deployed at:", address(marketplace));
    }
}
