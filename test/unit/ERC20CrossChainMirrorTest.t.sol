//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC20CrossChainMirror} from "../../src/ERC20CrossChainMirror.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployERC20CrossChainMirror} from "../../script/DeployERC20CrossChainMirror.s.sol";
import {MockBnM} from "../mocks/MockBnM.sol";
import {MockLnM} from "../mocks/MockLnM.sol";

contract ERC20CrossChainMirrorTest is Test {
    ERC20CrossChainMirror erc20CrossChainMirror;
    HelperConfig helperConfig;
    MockBnM mockBnM;
    MockLnM mockLnM;
    uint256 constant MINT_AMOUNT = 100 ether;

    address USER = makeAddr("user");
    address OWNER = makeAddr("owner");

    //////////////////////
    // Events ////////////
    //////////////////////

    //////////////////////
    // Errors ////////////
    //////////////////////

    function setUp() external {
        DeployERC20CrossChainMirror deployERC20CrossChainMirror = new DeployERC20CrossChainMirror();
        (erc20CrossChainMirror, helperConfig) = deployERC20CrossChainMirror.run();
        // console.log("Test contract", address(this));

        (address router, address linkToken, address CCIP_BnM_address, address CCIP_LnM_address) =
            helperConfig.activeNetworkConfig();

        mockBnM = MockBnM(CCIP_BnM_address);
        mockLnM = MockLnM(CCIP_LnM_address);
    }

    function testMintERC20() external {
        uint256 initialBalance = mockLnM.balanceOf(USER);

        // Mint tokens
        vm.prank(OWNER);
        erc20CrossChainMirror.mintToken(address(mockLnM), USER, MINT_AMOUNT);

        // Check if the recipient's balance was correctly updated
        uint256 finalBalance = mockLnM.balanceOf(USER);
        assertEq(finalBalance, initialBalance + MINT_AMOUNT, "Minting did not increase the balance correctly");
    }
}
