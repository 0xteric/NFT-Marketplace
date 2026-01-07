// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/Marketplace.sol";

contract DeployMarketplace is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PK");

        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerKey);

        uint256 initialMarketplaceFee = 250;
        Marketplace marketplace = new Marketplace(initialMarketplaceFee);

        console2.log("Marketplace deployed at:", address(marketplace));

        vm.stopBroadcast();
    }
}
