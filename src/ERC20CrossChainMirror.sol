// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

interface IMintableERC20 is IERC20, IERC20Metadata {
    function mint(address to, uint256 amount) external;
}

contract ERC20CrossChainMirror is CCIPReceiver, OwnerIsCreator {
    struct DestinationChainConfig {
        address mirrorContract;
        address erc20Token;
        uint64 chainSelector;
    }

    // Custom errors to provide more descriptive revert messages.
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance.
    error NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when the withdrawal of Ether fails.
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector); // Used when the destination chain has not been allowlisted by the contract owner.
    error SourceChainNotAllowlisted(uint64 sourceChainSelector); // Used when the source chain has not been allowlisted by the contract owner.
    error SenderNotAllowlisted(address sender); // Used when the sender has not been allowlisted by the contract owner.
    error InvalidReceiverAddress(); // Used when the receiver address is 0.

    // Event emitted when a message is sent to another chain.
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        uint256 amount,
        address feeToken,
        uint256 fees
    );

    // Event emitted when a message is received from another chain.
    event MessageReceived(bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender, string text);

    // Event for logging the mint action
    event TokenMinted(address indexed token, address indexed to, uint256 amount);

    bytes32 private s_lastReceivedMessageId; // Store the last received messageId.
    uint256 private s_lastReceivedAmountToMint; // Store the last received message.

    // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 => bool) public allowlistedDestinationChains;

    // Mapping to keep track of allowlisted source chains.
    mapping(uint64 => bool) public allowlistedSourceChains;

    // Mapping to keep track of allowlisted senders.
    mapping(address => bool) public allowlistedSenders;

    IERC20 private s_linkToken;
    IERC20 private s_erc20Token;
    address private s_receiver;
    DestinationChainConfig public destinationChainConfig;

    /// @dev Modifier that checks if the chain with the given destinationChainSelector is allowlisted.
    /// @param _destinationChainSelector The selector of the destination chain.
    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        if (!allowlistedDestinationChains[_destinationChainSelector]) {
            revert DestinationChainNotAllowlisted(_destinationChainSelector);
        }
        _;
    }

    /// @dev Modifier that checks if the chain with the given sourceChainSelector is allowlisted and if the sender is allowlisted.
    /// @param _sourceChainSelector The selector of the destination chain.
    modifier onlyAllowlisted(uint64 _sourceChainSelector) {
        if (!allowlistedSourceChains[_sourceChainSelector]) {
            revert SourceChainNotAllowlisted(_sourceChainSelector);
        }
        _;
    }

    /// @dev Modifier that checks the receiver address is not 0.
    /// @param _receiver The receiver address.
    modifier validateReceiver(address _receiver) {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        _;
    }

    constructor(address _router, address _link, address _erc20) CCIPReceiver(_router) {
        s_linkToken = IERC20(_link);
        s_erc20Token = IERC20(_erc20);
    }

    /// @dev Updates the allowlist status of a destination chain for transactions.
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) internal onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    /// @dev Updates the allowlist status of a source chain for transactions.
    function allowlistSourceChain(uint64 _sourceChainSelector, bool allowed) internal onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
    }

    function setReceiver(address receiver) external {
        s_receiver = receiver;
    }

    function setDestinationChainConfig(address mirrorContract, address erc20token) external {
        destinationChainConfig.mirrorContract = mirrorContract;
        destinationChainConfig.erc20Token = erc20token;
        if (block.chainid == 11155111) {
            destinationChainConfig.chainSelector = 12532609583862916517;
            allowlistSourceChain(16015286601757825753, true);
            allowlistDestinationChain(12532609583862916517, true);
        } else if (block.chainid == 80001) {
            destinationChainConfig.chainSelector = 16015286601757825753;
            allowlistSourceChain(12532609583862916517, true);
            allowlistDestinationChain(16015286601757825753, true);
        } else {
            revert("Contract only works between Sepolia and Mumbai");
        }
    }

    /// @notice Sends data to receiver on the destination chain.
    /// @notice Pay for fees in LINK.
    /// @dev Assumes your contract has sufficient LINK.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _amount The amount to be minted cross chain
    /// @return messageId The ID of the CCIP message that was sent.
    function sendMessagePayLINK(uint64 _destinationChainSelector, address _receiver, uint256 _amount)
        internal
        onlyOwner
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        validateReceiver(_receiver)
        returns (bytes32 messageId)
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(_receiver, _amount, address(s_linkToken));

        // Initialize a router client instance to interact with cross-chain router
        IRouterClient router = IRouterClient(this.getRouter());

        // Get the fee required to send the CCIP message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (fees > s_linkToken.balanceOf(address(this))) {
            revert NotEnoughBalance(s_linkToken.balanceOf(address(this)), fees);
        }

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        s_linkToken.approve(address(router), fees);

        // Send the CCIP message through the router and store the returned CCIP message ID
        messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit MessageSent(messageId, _destinationChainSelector, _receiver, _amount, address(s_linkToken), fees);

        // Return the CCIP message ID
        return messageId;
    }

    /// @notice Sends data to receiver on the destination chain.
    /// @notice Pay for fees in native gas.
    /// @dev Assumes your contract has sufficient native gas tokens.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _amount The amount to be minted cross chain
    /// @return messageId The ID of the CCIP message that was sent.
    function sendMessagePayNative(uint64 _destinationChainSelector, address _receiver, uint256 _amount)
        external
        onlyOwner
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        validateReceiver(_receiver)
        returns (bytes32 messageId)
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(_receiver, _amount, address(0));

        // Initialize a router client instance to interact with cross-chain router
        IRouterClient router = IRouterClient(this.getRouter());

        // Get the fee required to send the CCIP message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (fees > address(this).balance) {
            revert NotEnoughBalance(address(this).balance, fees);
        }

        // Send the CCIP message through the router and store the returned CCIP message ID
        messageId = router.ccipSend{value: fees}(_destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit MessageSent(messageId, _destinationChainSelector, _receiver, _amount, address(0), fees);

        // Return the CCIP message ID
        return messageId;
    }

    /// handle a received message
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector) // Make sure source chain and sender are allowlisted
    {
        s_lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        s_lastReceivedAmountToMint = abi.decode(any2EvmMessage.data, (uint256)); // abi-decoding of the sent text

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            abi.decode(any2EvmMessage.data, (string))
        );
    }

    /// @notice Construct a CCIP message.
    /// @dev This function will create an EVM2AnyMessage struct with all the necessary information for sending a text.
    /// @param _receiver The address of the receiver.
    /// @param _amount The amount to be minted crosschain
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.
    function _buildCCIPMessage(address _receiver, uint256 _amount, address _feeTokenAddress)
        private
        pure
        returns (Client.EVM2AnyMessage memory)
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver), // ABI-encoded receiver address
            data: abi.encode(_amount), // ABI-encoded amount
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array aas no tokens are transferred
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit
                Client.EVMExtraArgsV1({gasLimit: 200_000})
                ),
            // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
            feeToken: _feeTokenAddress
        });
    }

    /// @notice Fetches the details of the last received message.
    /// @return messageId The ID of the last received message.
    /// @return amount The last received amount.
    function getLastReceivedMessageDetails() external view returns (bytes32 messageId, uint256 amount) {
        return (s_lastReceivedMessageId, s_lastReceivedAmountToMint);
    }

    // Function to mint tokens
    function mintToken(address tokenAddress, address to, uint256 amount) external onlyOwner {
        require(tokenAddress != address(0), "TokenMinter: tokenAddress is the zero address");
        require(to != address(0), "TokenMinter: to is the zero address");

        IMintableERC20 token = IMintableERC20(tokenAddress);
        token.mint(to, amount);

        emit TokenMinted(tokenAddress, to, amount);

        // Aquí ejecutamos la llamada cross-chain a la función mintAndBridge del contrato desplegado en la red 2
        if (destinationChainConfig.chainSelector == 0) revert("Destination chain info not set");
        sendMessagePayLINK(destinationChainConfig.chainSelector, destinationChainConfig.mirrorContract, amount);
    }

    function mintAndBridge(address tokenAddress, address to, uint256 amount) internal {
        require(tokenAddress != address(0), "TokenMinter: tokenAddress is the zero address");
        require(to != address(0), "TokenMinter: to is the zero address");

        IMintableERC20 token = IMintableERC20(tokenAddress);
        token.mint(to, amount);

        emit TokenMinted(tokenAddress, to, amount);

        // Aquí ejecutamos el envío del token desde la red 2 a la red 1
    }
}
