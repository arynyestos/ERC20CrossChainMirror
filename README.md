# TDD ERC20 Cross-chain Mirror Contracts

## Introduction

This repo showcases the design process of a system with two mirror (or twin, as the code is the same for both) contracts that would be deployed on two different blockchains and behave in the following way:
    - When called, the contract on chain 1 (e.g., Sepolia) mints the specified amount of a token A
    - After minting, contract 1 sends a message to its twin contract on chain 2 (e.g., Mumbai) featuring the aforementioned amount.
    - Upon receiving the message, the contract on chain 2 mints the same amount of token B as minted on chain 1 of token A by its twin contract.
    - After minting, contract 2 bridges all the tokens minted over to its mirror contract on chain 1.

Thus, the result of a workflow initiated by a transaction sent to contract 1 to have it mint 100 tokens A would be 100 tokens A and 100 tokens B stored by contract 1.

Also, Test Driven Design was the required methodology for this challenge and it was followed strictly, as will be explained below.

## Design choices

- Testing environment: the framework of choice was Foundry, due to its comprehensive and fast testing features, as well as the possibility it provides to use Solidity as the only programming language both for developing and testing.
- Cross-chain communication: considering the requirements for this project, the tool chosen to accomplish the task was [Chainlink's CCIP](https://docs.chain.link/ccip/).

## Some consideratons

- Due to the fact that the goal of this project was to use the TDD methodology, which can only be done in a local testing environment, to create a cross-chain system, only one address could be specified in the tests for each token (instead of one for each chain), as well as for the CCIP router (which also has a different address on each chain it is deployed on).
- A key resource to be able to properly complete the task was the [MockCCIPRouter](https://github.com/smartcontractkit/ccip/blob/ccip-develop/contracts%2Fsrc%2Fv0.8%2Fccip%2Ftest%2Fmocks%2FMockRouter.sol) contract, which was not easy to find, since it does not come with the default installation of CCIP.

## Test Driven Design process

Five different tests were created to drive the development of the system:
    1. testMintERC20 would have to be fulfilled to check that upon calling of the function mintToken on the contract on chain 1, the token A (which in a live testnet could be the CCIP LnM token), got minted.
    2. testMessageSentAfterMint would ensure that the message conveying the minted amount to the twin contract on chain 2 got sent.
    3. testMessageReceivedOnTwinContract would, upon fulfillment prove that the message gets received by the contract on chain 2.
    4. testTokensMintedOnMessageReceived checked that token B (which in a live testnet could be the CCIP BnM token) got minted by the twin contract on chain 2 in the same amount as token A on chain 1.
    5. testTokensMintedAndBridgedOnMessageReceived ensured that, after minting, contract 2 bridged all the tokens B back to its mirror contract on chain 1.

Below can be seen the passing results of all five tests, once the functionality they aimed to verify was implemented, which was done sequentially, one at a time:

