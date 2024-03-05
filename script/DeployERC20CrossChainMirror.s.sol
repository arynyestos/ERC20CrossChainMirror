//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ERC20CrossChainMirror} from "../src/ERC20CrossChainMirror.sol";
import {console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockCCIPRouter} from "../test/mocks/MockCCIPRouter.sol";

contract DeployERC20CrossChainMirror is Script {
    address OWNER = makeAddr("owner");
    address erc20ToMint; // The address of the ERC20 token minted by the mirror contract
    address erc20ToReceive; // The address of the ERC20 token received crosschain by the mirror contract

    function run() external returns (ERC20CrossChainMirror, HelperConfig) {
        // Before startBroadcast -> not a "real" tx
        HelperConfig helperConfig = new HelperConfig();
        (address routerAddress, address linkTokenAddress, address CCIP_BnM_address, address CCIP_LnM_address,) =
            helperConfig.activeNetworkConfig();

        if (block.chainid == 11155111) {
            // Same config here for Sepolia and Anvil
            erc20ToMint = CCIP_LnM_address;
            erc20ToReceive = CCIP_BnM_address;
        } else if (block.chainid == 80001) {
            erc20ToMint = CCIP_BnM_address;
            erc20ToReceive = CCIP_LnM_address;
        }

        vm.startBroadcast();
        // After startBroadcast -> "real" tx
        ERC20CrossChainMirror erc20CrossChainMirror = new ERC20CrossChainMirror(
            routerAddress, IERC20(linkTokenAddress), IERC20(erc20ToMint), IERC20(erc20ToReceive)
        );
        // erc20CrossChainMirror.transferOwnership(OWNER); // Only for tests!!!
        vm.stopBroadcast();
        return (erc20CrossChainMirror, helperConfig);
    }
}
