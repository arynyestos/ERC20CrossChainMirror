// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

import {console} from "forge-std/Test.sol";

interface ITokenToMint is IERC20 {
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
    // error DestinationChainNotAllowlisted(uint64 destinationChainSelector); // Used when the destination chain has not been allowlisted by the contract owner.
    // error SourceChainNotAllowlisted(uint64 sourceChainSelector); // Used when the source chain has not been allowlisted by the contract owner.
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
    event MessageReceived(
        bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender, uint256 amount
    );

    // Event for logging the mint action
    event TokenMinted(address indexed token, address indexed to, uint256 amount);

    // The chain selector of the destination chain.
    // The address of the receiver on the destination chain.
    // The token address that was transferred.
    // The token amount that was transferred.
    // the token address used to pay CCIP fees.
    // The fees paid for sending the message.
    event TokensTransferred( // The unique ID of the message.
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    // The chain selector of the source chain.
    // The address of the sender from the source chain.
    // The text that was received.
    // The token address that was transferred.
    // The token amount that was transferred.
    event TokenReceived( // The unique ID of the CCIP message.
    bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender, address token, uint256 tokenAmount);

    bytes32 private s_lastReceivedMessageId; // Store the last received messageId.
    uint256 private s_lastReceivedAmountToMint; // Store the last received message.
    address private s_lastReceivedTokenAddress; // Store the last received token address.
    uint256 private s_lastReceivedTokenAmount; // Store the last received token amount.

    // Mapping to keep track of allowlisted destination chains.
    // mapping(uint64 => bool) public allowlistedDestinationChains;

    // Mapping to keep track of allowlisted source chains.
    // mapping(uint64 => bool) public allowlistedSourceChains;

    // Mapping to keep track of allowlisted senders.
    mapping(address => bool) public allowlistedSenders;

    IERC20 private immutable i_linkToken;
    IERC20 private immutable i_erc20TokenToMint;
    IERC20 private immutable i_erc20TokenToReceive;
    address private s_receiver;
    DestinationChainConfig public destinationChainConfig;

    /// @dev Modifier that checks if the chain with the given destinationChainSelector is allowlisted.
    /// @param _destinationChainSelector The selector of the destination chain.
    // modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
    //     if (!allowlistedDestinationChains[_destinationChainSelector]) {
    //         revert DestinationChainNotAllowlisted(_destinationChainSelector);
    //     }
    //     _;
    // }

    /// @dev Modifier that checks if the chain with the given sourceChainSelector is allowlisted and if the sender is allowlisted.
    /// @param _sourceChainSelector The selector of the destination chain.
    // modifier onlyAllowlisted(uint64 _sourceChainSelector) {
    //     if (!allowlistedSourceChains[_sourceChainSelector]) {
    //         revert SourceChainNotAllowlisted(_sourceChainSelector);
    //     }
    //     _;
    // }

    /// @dev Modifier that checks the receiver address is not 0.
    /// @param _receiver The receiver address.
    modifier validateReceiver(address _receiver) {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        _;
    }

    constructor(address _router, IERC20 _link, IERC20 _erc20TokenToMint, IERC20 _erc20TokenToReceive)
        CCIPReceiver(_router)
    {
        i_linkToken = _link;
        i_erc20TokenToMint = _erc20TokenToMint;
        i_erc20TokenToReceive = _erc20TokenToReceive;
    }

    /// @dev Updates the allowlist status of a destination chain for transactions.
    // function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) internal onlyOwner {
    //     allowlistedDestinationChains[_destinationChainSelector] = allowed;
    // }

    /// @dev Updates the allowlist status of a source chain for transactions.
    // function allowlistSourceChain(uint64 _sourceChainSelector, bool allowed) internal onlyOwner {
    //     allowlistedSourceChains[_sourceChainSelector] = allowed;
    // }

    function setReceiver(address receiver) external {
        s_receiver = receiver;
    }

    function setDestinationChainConfig(address mirrorContract, uint64 destinationChainSelector) external {
        destinationChainConfig.mirrorContract = mirrorContract;
        destinationChainConfig.chainSelector = destinationChainSelector;
    }

    /// @notice Sends data to receiver on the destination chain.
    /// @notice Pay for fees in LINK.
    /// @dev Assumes your contract has sufficient LINK.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _amount The amount to be minted cross chain
    /// @return messageId The ID of the CCIP message that was sent.
    function sendMessagePayLINK(uint64 _destinationChainSelector, address _receiver, uint256 _amount)
        internal
        onlyOwner
        /*onlyAllowlistedDestinationChain(_destinationChainSelector)*/
        validateReceiver(_receiver)
        returns (bytes32 messageId)
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(_receiver, _amount, address(i_linkToken));

        // Initialize a router client instance to interact with cross-chain router
        IRouterClient router = IRouterClient(this.getRouter());

        // Get the fee required to send the CCIP message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);
        console.log("The fees to send the message are:", fees);
        console.log("The LINK balance of the mirror contract is:", i_linkToken.balanceOf(address(this)));

        if (fees > i_linkToken.balanceOf(address(this))) {
            revert NotEnoughBalance(i_linkToken.balanceOf(address(this)), fees);
        }

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        i_linkToken.approve(address(router), fees);

        // Send the CCIP message through the router and store the returned CCIP message ID
        messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit MessageSent(messageId, _destinationChainSelector, _receiver, _amount, address(i_linkToken), fees);

        // Return the CCIP message ID
        return messageId;
    }

    /// @notice Transfer tokens to receiver on the destination chain.
    /// @notice pay in LINK.
    /// @notice the token must be in the list of supported tokens.
    /// @notice This function can only be called by the owner.
    /// @dev Assumes your contract has sufficient LINK tokens to pay for the fees.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _token token address.
    /// @param _amount token amount.
    /// @return messageId The ID of the message that was sent.
    function transferTokensPayLINK(uint64 _destinationChainSelector, address _receiver, address _token, uint256 _amount)
        internal
        // onlyOwner
        // onlyAllowlistedChain(_destinationChainSelector)
        validateReceiver(_receiver)
        returns (bytes32 messageId)
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        //  address(linkToken) means fees are paid in LINK
        Client.EVM2AnyMessage memory evm2AnyMessage =
            _buildCCIPTokenTransferMessage(_receiver, _token, _amount, address(i_linkToken));

        IRouterClient router = IRouterClient(this.getRouter());
        // Get the fee required to send the message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);
        console.log("The fees to send the tokens are:", fees);
        console.log("The LINK balance of the mirror contract is:", i_linkToken.balanceOf(address(this)));

        if (fees > i_linkToken.balanceOf(address(this))) {
            revert NotEnoughBalance(i_linkToken.balanceOf(address(this)), fees);
        }

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        i_linkToken.approve(address(router), fees);

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        IERC20(_token).approve(address(router), _amount);

        // Send the message through the router and store the returned message ID
        messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit TokensTransferred(
            messageId, _destinationChainSelector, _receiver, _token, _amount, address(i_linkToken), fees
        );

        // Return the message ID
        return messageId;
    }

    /// handle a received message
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override 
    /*onlyAllowlisted(any2EvmMessage.sourceChainSelector)*/
    // Make sure source chain and sender are allowlisted
    {
        s_lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        s_lastReceivedAmountToMint = abi.decode(any2EvmMessage.data, (uint256)); // abi-decoding of the sent amount
        if (any2EvmMessage.destTokenAmounts.length > 0) {
            s_lastReceivedTokenAddress = any2EvmMessage.destTokenAmounts[0].token;
            s_lastReceivedTokenAmount = any2EvmMessage.destTokenAmounts[0].amount;
        }

        console.log("The message received says the amount to mint and send back is:", s_lastReceivedAmountToMint);

        if (s_lastReceivedAmountToMint != 0) {
            emit MessageReceived(
                any2EvmMessage.messageId,
                any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
                abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
                s_lastReceivedAmountToMint
            );
            mintAndBridge(s_lastReceivedAmountToMint);
        } else {
            emit TokenReceived(
                any2EvmMessage.messageId,
                any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
                abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
                any2EvmMessage.destTokenAmounts[0].token,
                any2EvmMessage.destTokenAmounts[0].amount
            );
        }
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
        // Set the token to zero, since we're sending a message
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(0), amount: 0});

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver), // ABI-encoded receiver address
            data: abi.encode(_amount), // ABI-encoded amount
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array as no tokens are transferred
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit
                Client.EVMExtraArgsV1({gasLimit: 400_000})
                ),
            // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
            feeToken: _feeTokenAddress
        });
    }

    function _buildCCIPTokenTransferMessage(
        address _receiver,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) private pure returns (Client.EVM2AnyMessage memory) {
        // Set the token amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: _token, amount: _amount});

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver), // ABI-encoded receiver address
            data: abi.encode(0), // No data
            tokenAmounts: tokenAmounts, // The amount and type of token being transferred
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 200_000})),
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
    /// @notice Fetches the details of the last received message.
    /// @return tokenAddress The ID of the last received message.
    /// @return tokenAmount The last received amount.

    function getLastReceivedTokenDetails() external view returns (address tokenAddress, uint256 tokenAmount) {
        return (s_lastReceivedTokenAddress, s_lastReceivedTokenAmount);
    }

    // Function to mint tokens
    function mintToken(uint256 amount) external onlyOwner {
        ITokenToMint token = ITokenToMint(address(i_erc20TokenToMint));
        token.mint(address(this), amount);

        emit TokenMinted(address(i_erc20TokenToMint), address(this), amount);

        // Send message to the twin contract on chain 2 specifying the amount of A that was minted
        if (destinationChainConfig.chainSelector == 0) revert("Destination chain info not set");
        sendMessagePayLINK(destinationChainConfig.chainSelector, destinationChainConfig.mirrorContract, amount);
    }

    function mintAndBridge(uint256 amount) internal {
        ITokenToMint token = ITokenToMint(address(i_erc20TokenToMint));
        token.mint(address(this), amount);

        emit TokenMinted(address(i_erc20TokenToMint), address(this), amount);

        // After minting the same amount that was minted on chain 1 of token A, send these tokens B back to the twin contract on chain 1
        if (destinationChainConfig.chainSelector == 0) revert("Destination chain info not set");
        transferTokensPayLINK(
            destinationChainConfig.chainSelector,
            destinationChainConfig.mirrorContract,
            address(i_erc20TokenToMint),
            amount
        );
    }
}
