//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ERC20CrossChainMirror} from "../src/ERC20CrossChainMirror.sol";
import {console} from "forge-std/Test.sol";

contract DeployERC20CrossChainMirror is Script {
    address OWNER = makeAddr("owner");
    address erc20Address;

    function run() external returns (ERC20CrossChainMirror, HelperConfig) {
        // Before startBroadcast -> not a "real" tx
        HelperConfig helperConfig = new HelperConfig(); // This comes with our mocks!
        (address routerAddress, address linkTokenAddress, address CCIP_BnM_address, address CCIP_LnM_address) =
            helperConfig.activeNetworkConfig();

        if (block.chainid == 11155111) {
            erc20Address = CCIP_LnM_address;
        } else if (block.chainid == 80001) {
            erc20Address = CCIP_BnM_address;
        } else {
            erc20Address = address(1234);
        }

        vm.startBroadcast();
        // After startBroadcast -> "real" tx
        ERC20CrossChainMirror erc20CrossChainMirror =
            new ERC20CrossChainMirror(routerAddress, linkTokenAddress, erc20Address);
        erc20CrossChainMirror.transferOwnership(OWNER); // Only for tests!!!
        vm.stopBroadcast();
        return (erc20CrossChainMirror, helperConfig);
    }
}
