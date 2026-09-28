// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Forwarder} from "../src/Forwarder.sol";

/// Usage: OWNER=0x... DESTINATION=0x... forge script script/Deploy.s.sol --rpc-url <rpc> --account <keystore> --broadcast
contract Deploy is Script {
    function run() external returns (Forwarder fwd) {
        address owner = vm.envAddress("OWNER");
        address destination = vm.envAddress("DESTINATION");

        vm.startBroadcast();
        fwd = new Forwarder(owner, destination);
        vm.stopBroadcast();

        console.log("Forwarder:  ", address(fwd));
        console.log("Owner:      ", fwd.owner());
        console.log("Destination:", fwd.destination());
    }
}
