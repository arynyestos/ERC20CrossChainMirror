// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockBnM} from "../test/mocks/MockBnM.sol";
import {MockLnM} from "../test/mocks/MockLnM.sol";
import {MockCCIPRouter} from "../test/mocks/MockCCIPRouter.sol";
import {MockLink} from "../test/mocks/MockLink.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address routerAddress;
        address linkTokenAddress;
        address CCIP_BnM_address;
        address CCIP_LnM_address;
        uint64 chainSelector;
    }

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else if (block.chainid == 80001) {
            activeNetworkConfig = getMumbaiConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaConfig() public pure returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            routerAddress: 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59,
            linkTokenAddress: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            CCIP_BnM_address: 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05,
            CCIP_LnM_address: 0x466D489b6d36E7E3b824ef491C225F5830E81cC1,
            chainSelector: 16015286601757825753
        });
    }

    function getMumbaiConfig() public pure returns (NetworkConfig memory mumbaiNetworkConfig) {
        mumbaiNetworkConfig = NetworkConfig({
            routerAddress: 0x1035CabC275068e0F4b745A29CEDf38E13aF41b1,
            linkTokenAddress: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB,
            CCIP_BnM_address: 0xf1E3A5842EeEF51F2967b3F05D45DD4f4205FF40,
            CCIP_LnM_address: 0xc1c76a8c5bFDE1Be034bbcD930c668726E7C1987,
            chainSelector: 12532609583862916517
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we already have an active network config
        if (activeNetworkConfig.CCIP_BnM_address != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockCCIPRouter mockCCIPRouter = new MockCCIPRouter();
        // LinkToken mockLinkToken = new LinkToken();
        MockLink mockLinkToken = new MockLink();
        MockBnM mockBnM = new MockBnM();
        MockLnM mockLnM = new MockLnM();
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            routerAddress: address(mockCCIPRouter),
            linkTokenAddress: address(mockLinkToken),
            CCIP_BnM_address: address(mockBnM),
            CCIP_LnM_address: address(mockLnM),
            // chainSelector: uint64(123456)
            chainSelector: 12532609583862916517
        });
    }
}
