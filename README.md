# TDD ERC20 Cross-Chain Mirror Contracts

## Table of Contents
- [Introduction](#introduction)
- [Design choices](#design-choices)
- [Some consideratons](#some-considerations)
- [Test Driven Design process](#test-driven-design-process)
- [Usage](#usage)
- [Future Improvements](#future-improvements)

## Introduction

This repo showcases the design process of a system with two mirror (or twin, as the code is the same for both) contracts that would be deployed on two different blockchains and behave in the following way:
- When called, the contract on chain 1 (e.g., Sepolia) mints the specified amount of a token A.
- After minting, contract 1 sends a message to its twin contract on chain 2 (e.g., Mumbai) featuring the aforementioned amount.
- Upon receiving the message, the contract on chain 2 mints the same amount of token B as minted on chain 1 of token A by its twin contract.
- After minting, contract 2 bridges all the tokens minted over to its mirror contract on chain 1.

Thus, the result of a workflow initiated by a transaction sent to contract 1 to have it mint 100 tokens A would be 100 tokens A and 100 tokens B stored by contract 1.

Also, Test Driven Design was the required methodology for this challenge and it was followed strictly, as will be explained below.

## Design Choices

- Testing environment: the framework of choice was Foundry, due to its comprehensive and fast testing features, as well as the possibility it provides to use Solidity as the only programming language both for developing and testing.
- Cross-chain communication: considering the requirements for this project, the tool chosen to accomplish the task was [Chainlink's CCIP](https://docs.chain.link/ccip/).

## Some Consideratons

- Due to the fact that the goal of this project was to use the TDD methodology, which can only be done in a local testing environment, to create a cross-chain system, only one address could be specified in the tests for each token (instead of one for each token on each chain), as well as for the CCIP router (which also has a different address on each chain it is deployed on).
- A key resource to be able to properly complete the task was the [MockCCIPRouter](https://github.com/smartcontractkit/ccip/blob/ccip-develop/contracts%2Fsrc%2Fv0.8%2Fccip%2Ftest%2Fmocks%2FMockRouter.sol) contract, which was not easy to find, since it does not come with the default installation of CCIP.

## Test Driven Design Process

Five different tests were created to drive the development of the system:
1. testMintERC20 would have to be fulfilled to check that upon calling of the function `mintToken()` on the contract on chain 1, the token A (which in a live testnet could be the CCIP LnM token), got minted.
2. testMessageSentAfterMint would ensure that the message conveying the minted amount to the twin contract on chain 2 got sent.
3. testMessageReceivedOnTwinContract would, upon fulfillment prove that the message gets received by the contract on chain 2.
4. testTokensMintedOnMessageReceived checked that token B (which in a live testnet could be the CCIP BnM token) got minted by the twin contract on chain 2 in the same amount as token A on chain 1.
5. testTokensMintedAndBridgedOnMessageReceived ensured that, after minting, contract 2 bridged all the tokens B back to its mirror contract on chain 1.

Below can be seen the passing results of all five tests, once the functionality they aimed to verify was implemented, which was done sequentially, one at a time:
#### testMintERC20
![Test 1](https://github.com/arynyestos/ERC20CrossChainMirror/assets/33223441/fdf1c9f6-bf73-4c90-a283-811ad8bf6765)

#### testMessageSentAfterMint
![Test 2](https://github.com/arynyestos/ERC20CrossChainMirror/assets/33223441/7ad1a7b7-eea3-4559-a583-40f176e4d4ee)

#### testMessageReceivedOnTwinContract
![Test 3](https://github.com/arynyestos/ERC20CrossChainMirror/assets/33223441/aaa275d5-6fcf-4f9d-b7ed-926e2176132b)

#### testTokensMintedOnMessageReceived
![Test 4](https://github.com/arynyestos/ERC20CrossChainMirror/assets/33223441/a544c70e-0edc-4355-96c6-3a00e5a50188)

#### testTokensMintedAndBridgedOnMessageReceived
![Test 5](https://github.com/arynyestos/ERC20CrossChainMirror/assets/33223441/3ab8f889-c777-4f2a-9658-c2dec299ae72)

However, after the functionality for each test was achieved and it passed, implementing the functionality enforced by the following test caused the previous one to fail. This was because the addition of the subsequential actions to be performed, which needed further setup that had not been necessary in previous tests, caused the transactions to revert. Of course, for a real project this would have to be corrected, since the goal is for all tests to pass, however, this being a challenge in which TDD was mandatory, leaving the tests as they were before the full functionality was implemented seemed like a good way to prove said methodology was followed. Thus, below can be seen how, at the end of the design process, the only passing test was the last one, while all the others, as explained, lacked the necessary setup for the transactions initiated in them not to revert.

<p align="center">
  <img src="https://github.com/arynyestos/ERC20CrossChainMirror/assets/33223441/74f7a113-aaa9-4de3-b461-db7e2f64777f">
</p>

## Usage

In order to try out the ERC20 Cross-chain Mirror system yourself, follow these steps:
1. Make sure you have [Foundry](https://book.getfoundry.sh/getting-started/installation) installed.
3. Clone the repo:
```bash
git clone https://github.com/arynyestos/ERC20CrossChainMirror.git
cd ERC20CrossChainMirror
```
3. Install the necessary dependencies:
```bash
forge install OpenZeppelin/openzeppelin-contracts --no-commit
npm install @chainlink/contracts-ccip --save
```
As you can see, CCIP installation needed to be done using the NPM package manager. However, the following command should work too, although it would require tweaking the `remappings` in the `foundry.toml` file:
```bash
forge install smartcontractkit/ccip@v2.8.0-ccip1.4.2-release --no-commit
```
4. Run the tests:
```bash
forge test
```

If you want to run each test separately as was done throughout the process described above you can just comment out all the functionality in the `mintToken()` and `mintAndBridge()` functions that happens later in the workflow than the one it intends to verify. For example, in order to run the testMintERC20 test successfully, comment out all the lines in those two functions except for these:
```Solidity
        ITokenToMint token = ITokenToMint(address(i_erc20TokenToMint));
        token.mint(address(this), amount);

        emit TokenMinted(address(i_erc20TokenToMint), address(this), amount);
```
And run:
```bash
forge test --mt testMintERC20
```

## Future Improvements

The most obvious future improvement would be to deploy the system on two live testnets. However, this was out of scope for this challenge, in which TDD was a must.
