//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC20CrossChainMirror} from "../../src/ERC20CrossChainMirror.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployERC20CrossChainMirror} from "../../script/DeployERC20CrossChainMirror.s.sol";
import {MockBnM} from "../mocks/MockBnM.sol";
import {MockLnM} from "../mocks/MockLnM.sol";
import {MockLink} from "../mocks/MockLink.sol";
import {MockCCIPRouter} from "../mocks/MockCCIPRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC20CrossChainMirrorTest is Test {
    ERC20CrossChainMirror erc20CrossChainMirrorMumbai;
    ERC20CrossChainMirror erc20CrossChainMirrorSepolia;
    HelperConfig helperConfigMumbai;
    HelperConfig helperConfigSepolia;
    // MockBnM mockBnM_Mumbai;
    // MockBnM mockBnM_Sepolia;
    // MockLnM mockLnM_Mumbai;
    // MockLnM mockLnM_Sepolia;
    MockBnM mockBnM; // Only one local testnet -> only one address for each ERC20 token
    MockLnM mockLnM;
    MockLink mockLinkMumbai;
    MockLink mockLinkSepolia;
    MockCCIPRouter mockCcipRouterMumbai;
    MockCCIPRouter mockCcipRouterSepolia; // The router is the same for both mirror contracts, since we only have one local testnet
    uint64 chainSelectorMumbai;
    uint64 chainSelectorSepolia;
    uint256 constant MINT_AMOUNT = 100 ether;
    uint256 constant LINK_AMOUNT_FOR_FEES = 100 ether;

    address OWNER = makeAddr("owner");

    //////////////////////
    // Events ////////////
    //////////////////////

    event TokenMinted(address indexed token, address indexed to, uint256 amount);

    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        uint256 amount,
        address feeToken,
        uint256 fees
    );

    event MessageReceived(
        bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender, uint256 amount
    );

    event TokensTransferred( // The unique ID of the message.
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    //////////////////////
    // Errors ////////////
    //////////////////////

    function setUp() external {
        // Deployment on chain A (e. g. Sepolia)
        helperConfigSepolia = new HelperConfig();
        // The router will be the same for both mirror contracts, since we only have one local Anvil chain
        (
            address router,
            address linkTokenSepolia,
            address CCIP_BnM_Sepolia,
            address CCIP_LnM_Sepolia,
            // uint64 _chainSelectorSepolia
        ) = helperConfigSepolia.activeNetworkConfig();
        erc20CrossChainMirrorSepolia = new ERC20CrossChainMirror(
            router, IERC20(linkTokenSepolia), IERC20(CCIP_LnM_Sepolia), IERC20(CCIP_BnM_Sepolia)
        );

        console.log("Sepolia mirror", address(erc20CrossChainMirrorSepolia));
        erc20CrossChainMirrorSepolia.transferOwnership(OWNER);
        vm.prank(OWNER);
        erc20CrossChainMirrorSepolia.acceptOwnership();

        chainSelectorSepolia = 16015286601757825753;
        mockBnM = MockBnM(CCIP_BnM_Sepolia);
        mockLnM = MockLnM(CCIP_LnM_Sepolia);
        console.log("Address of LnM:", CCIP_LnM_Sepolia);
        console.log("Address of BnM:", CCIP_BnM_Sepolia);
        mockLinkSepolia = MockLink(linkTokenSepolia);
        mockCcipRouterSepolia = MockCCIPRouter(router);

        // Deployment on chain B (e. g. Mumbai)
        helperConfigMumbai = new HelperConfig();
        // The router will be the same for both mirror contracts, since we only have one local Anvil chain
        (, address linkTokenMumbai, /*address CCIP_BnM_Mumbai, address CCIP_LnM_Mumbai,*/,, uint64 _chainSelectorMumbai)
        = helperConfigMumbai.activeNetworkConfig();
        erc20CrossChainMirrorMumbai = new ERC20CrossChainMirror(
            router, IERC20(linkTokenMumbai), IERC20(CCIP_BnM_Sepolia), IERC20(CCIP_LnM_Sepolia)
        );

        console.log("Mumbai mirror", address(erc20CrossChainMirrorMumbai));
        erc20CrossChainMirrorMumbai.transferOwnership(OWNER);
        vm.prank(OWNER);
        erc20CrossChainMirrorMumbai.acceptOwnership();

        chainSelectorMumbai = _chainSelectorMumbai;
        // mockBnM_Mumbai = MockBnM(CCIP_BnM_Mumbai);
        // mockLnM_Mumbai = MockLnM(CCIP_LnM_Mumbai);
        mockLinkMumbai = MockLink(linkTokenMumbai);
        mockCcipRouterMumbai = MockCCIPRouter(router); // Same as "Sepolia"

        console.log("Router address", router);
    }

    function testMintERC20() external {
        uint256 initialBalance = mockLnM.balanceOf(address(erc20CrossChainMirrorSepolia));

        // Mint LINK so the mirror contract can send messages
        mockLinkSepolia.mint(address(erc20CrossChainMirrorSepolia), LINK_AMOUNT_FOR_FEES);

        // Mint tokens
        vm.startPrank(OWNER);
        vm.expectEmit(true, true, true, false);
        emit TokenMinted(address(mockLnM), address(erc20CrossChainMirrorSepolia), MINT_AMOUNT);
        erc20CrossChainMirrorSepolia.mintToken(MINT_AMOUNT);
        vm.stopPrank();

        // Check if the recipient's balance was correctly updated
        uint256 finalBalance = mockLnM.balanceOf(address(erc20CrossChainMirrorSepolia));
        assertEq(finalBalance, initialBalance + MINT_AMOUNT, "Minting did not increase the balance correctly");
    }

    function testMessageSentAfterMint() external {
        // Mint LINK so the mirror contract can send messages
        mockLinkSepolia.mint(address(erc20CrossChainMirrorSepolia), LINK_AMOUNT_FOR_FEES);

        vm.startPrank(OWNER);
        erc20CrossChainMirrorSepolia.setDestinationChainConfig(
            address(erc20CrossChainMirrorMumbai), chainSelectorMumbai
        );
        vm.expectEmit(false, true, true, true); // Message ID mocking would be too much trouble
        emit MessageSent(
            bytes32(0),
            chainSelectorMumbai,
            address(erc20CrossChainMirrorMumbai),
            MINT_AMOUNT,
            address(mockLinkSepolia),
            0
        );
        erc20CrossChainMirrorSepolia.mintToken(MINT_AMOUNT);
        vm.stopPrank();
    }

    function testMessageReceivedOnTwinContract() external {
        // Mint LINK so the mirror contract can send messages
        mockLinkSepolia.mint(address(erc20CrossChainMirrorSepolia), LINK_AMOUNT_FOR_FEES);

        // Mint tokens
        vm.startPrank(OWNER);
        erc20CrossChainMirrorSepolia.setDestinationChainConfig(
            address(erc20CrossChainMirrorMumbai), chainSelectorMumbai
        );
        vm.expectEmit(false, true, true, true, address(erc20CrossChainMirrorMumbai)); // Message ID mocking would be too much trouble
        emit MessageReceived(bytes32(0), chainSelectorSepolia, address(erc20CrossChainMirrorSepolia), MINT_AMOUNT);
        erc20CrossChainMirrorSepolia.mintToken(MINT_AMOUNT);
        vm.stopPrank();
    }

    function testTokensMintedOnMessageReceived() external {
        uint256 initialBalance = mockBnM.balanceOf(address(erc20CrossChainMirrorMumbai));
        // Mint LINK so the mirror contract can send messages
        mockLinkSepolia.mint(address(erc20CrossChainMirrorSepolia), LINK_AMOUNT_FOR_FEES);

        // Mint tokens
        vm.startPrank(OWNER);
        erc20CrossChainMirrorSepolia.setDestinationChainConfig(
            address(erc20CrossChainMirrorMumbai), chainSelectorMumbai
        );
        vm.expectEmit(true, true, true, false);
        emit TokenMinted(address(mockBnM), address(erc20CrossChainMirrorMumbai), MINT_AMOUNT);
        erc20CrossChainMirrorSepolia.mintToken(MINT_AMOUNT);
        vm.stopPrank();

        uint256 finalBalance = mockBnM.balanceOf(address(erc20CrossChainMirrorMumbai));
        assertEq(finalBalance, initialBalance + MINT_AMOUNT, "Tokens not minted on message received");
    }

    function testTokensMintedAndBridgedOnMessageReceived() external {
        uint256 initialBalance = mockBnM.balanceOf(address(erc20CrossChainMirrorSepolia));
        // Mint LINK so the mirror contract can send messages
        mockLinkSepolia.mint(address(erc20CrossChainMirrorSepolia), LINK_AMOUNT_FOR_FEES);
        // Mint LINK so the other mirror contract can send tokens
        mockLinkMumbai.mint(address(erc20CrossChainMirrorMumbai), LINK_AMOUNT_FOR_FEES);

        // Mint tokens
        vm.startPrank(OWNER);
        erc20CrossChainMirrorSepolia.setDestinationChainConfig(
            address(erc20CrossChainMirrorMumbai), chainSelectorMumbai
        );
        vm.startPrank(OWNER);
        erc20CrossChainMirrorMumbai.setDestinationChainConfig(
            address(erc20CrossChainMirrorSepolia), chainSelectorSepolia
        );
        vm.expectEmit(true, true, true, false);
        emit TokenMinted(address(mockBnM), address(erc20CrossChainMirrorMumbai), MINT_AMOUNT);
        vm.expectEmit(false, true, true, true);
        emit TokensTransferred(
            bytes32(0),
            chainSelectorSepolia,
            address(erc20CrossChainMirrorSepolia),
            address(mockBnM),
            MINT_AMOUNT,
            address(mockLinkMumbai),
            0
        );
        erc20CrossChainMirrorSepolia.mintToken(MINT_AMOUNT);
        vm.stopPrank();

        uint256 finalBalance = mockBnM.balanceOf(address(erc20CrossChainMirrorSepolia));
        assertEq(finalBalance, initialBalance + MINT_AMOUNT, "Tokens not minted on message received");
    }
}
