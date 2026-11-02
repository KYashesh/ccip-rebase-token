# Cross Chain Rebase Token

A cross-chain, interest-bearing ERC-20 token protocol built using **Solidity, Foundry, and Chainlink CCIP**. The protocol allows users to deposit ETH into a vault, receive rebase tokens that accrue interest over time, and transfer their tokens across supported blockchain networks while preserving their individual interest rates.

## Overview

The Cross Chain Rebase Token protocol combines an interest-bearing token mechanism with cross-chain interoperability.

Users deposit ETH into a vault and receive an equivalent amount of Rebase Tokens (RBT). Their token balances increase over time based on their assigned interest rates. The protocol also integrates Chainlink's Cross-Chain Interoperability Protocol (CCIP) to enable token transfers between supported blockchain networks.

Unlike a traditional ERC-20 token, the balance of each user is calculated dynamically based on their principal balance, assigned interest rate, and elapsed time.

## Key Features

- **Interest-Bearing ERC-20 Token:** Users earn interest on their token balances over time.
- **Dynamic Rebase Mechanism:** Token balances increase through interest accrual without requiring users to manually claim rewards.
- **Individual Interest Rates:** Each user maintains an interest rate assigned when they deposit or receive tokens.
- **Decreasing Interest Rate:** The protocol owner can reduce the global interest rate, but cannot increase it.
- **ETH Deposit and Redemption:** Users can deposit ETH into the vault to mint RBT and redeem their tokens for ETH.
- **Cross-Chain Transfers:** Chainlink CCIP enables token transfers between supported blockchain networks.
- **Interest Rate Preservation:** User-specific interest rates are encoded and transferred alongside cross-chain token transfers.
- **Access-Controlled Minting and Burning:** Only authorized contracts can mint and burn tokens.

## Architecture

The protocol consists of three main smart contracts:

### 1. RebaseToken.sol

The main ERC-20 token contract responsible for managing token balances and interest calculations.

Responsibilities:
- Implements an interest-bearing ERC-20 token named `RebaseToken` (RBT).
- Calculates user balances using principal balances and accrued interest.
- Tracks individual user interest rates and timestamps.
- Mints accrued interest when users transfer, mint, or burn tokens.
- Allows the protocol owner to decrease the global interest rate.
- Uses role-based access control for minting and burning operations.

### 2. Vault.sol

The vault contract manages ETH deposits and redemptions.

Responsibilities:
- Accepts ETH deposits from users.
- Mints an equivalent amount of RBT to depositors.
- Assigns the current global interest rate to new depositors.
- Allows users to redeem RBT for the underlying ETH.
- Burns redeemed tokens before releasing ETH.

### 3. RebaseTokenPool.sol

The cross-chain token pool integrates the protocol with Chainlink CCIP.

Responsibilities:
- Extends Chainlink's `TokenPool` contract.
- Burns tokens on the source chain before a cross-chain transfer.
- Encodes the sender's individual interest rate into the cross-chain message data.
- Decodes the interest rate on the destination chain.
- Mints the corresponding tokens to the recipient while preserving their interest rate.

## How It Works

### Deposit and Interest Accrual

1. A user deposits ETH into the Vault.
2. The Vault retrieves the current global interest rate from RebaseToken.
3. The contract mints an equivalent amount of RBT to the user.
4. The user's individual interest rate is recorded.
5. Their token balance increases over time as interest accrues.

### Token Transfers

When a user transfers RBT:

1. The protocol calculates and mints the sender's accrued interest.
2. The recipient's accrued interest is also updated.
3. If the recipient has no existing balance, they inherit the sender's interest rate.
4. The token transfer is completed.

### Cross-Chain Transfers Using CCIP

1. The user initiates a cross-chain token transfer through the CCIP infrastructure.
2. The source token pool burns the tokens on the source chain.
3. The sender's individual interest rate is encoded into the pool data.
4. Chainlink CCIP facilitates the cross-chain message and token transfer.
5. The destination token pool decodes the transferred interest rate.
6. The destination RebaseToken contract mints the corresponding tokens to the recipient.
7. The recipient continues earning interest using the preserved interest rate.

## Technology Stack

| Technology | Purpose |
|---|---|
| Solidity | Smart contract development |
| Foundry | Development, testing, and deployment |
| Chainlink CCIP | Cross-chain interoperability |
| OpenZeppelin | ERC-20, ownership, and access control |
| Chainlink Local | Local CCIP simulation and fork testing |
| Ethereum Sepolia | Test network |
| Arbitrum Sepolia | Cross-chain destination test network |

## Project Structure

```text
ccip-rebase-token/
│
├── .github/
│   └── workflows/
│
├── lib/
│   ├── forge-std/
│   ├── openzeppelin-contracts/
│   ├── chainlink-ccip/
│   ├── chainlink-evm/
│   └── chainlink-local/
│
├── script/
│   ├── Deployer.s.sol
│   └── ...
│
├── src/
│   ├── interfaces/
│   │   └── IRebaseToken.sol
│   ├── RebaseToken.sol
│   ├── Vault.sol
│   └── RebaseTokenPool.sol
│
├── test/
│   ├── unit/
│   ├── integration/
│   └── ...
│
├── .gitignore
├── .gitmodules
├── foundry.lock
├── foundry.toml
└── README.md
```

## Getting Started

### Prerequisites

Make sure you have the following installed:

- [Git](https://git-scm.com/)
- [Foundry](https://getfoundry.sh/)
- [GitHub](https://github.com/)

### 1. Clone the Repository

```bash
git clone --recurse-submodules https://github.com/KYashesh/ccip-rebase-token.git

cd ccip-rebase-token
```

If you have already cloned the repository without its submodules, initialize them using:

```bash
git submodule update --init --recursive
```

### 2. Install Dependencies

The project uses Foundry and Git submodules for dependency management.

```bash
forge install
```

### 3. Configure Environment Variables

Create a `.env` file in the root directory:

```env
SEPOLIA_RPC_URL=your_sepolia_rpc_url
ARBITRUM_SEPOLIA_RPC_URL=your_arbitrum_sepolia_rpc_url
```

Replace the placeholders with your own RPC endpoints.

**Important:** Never commit your `.env` file or expose private keys and API credentials.

### 4. Build the Project

Compile the smart contracts:

```bash
forge build
```

### 5. Run Tests

Execute the test suite:

```bash
forge test
```

For more detailed test output:

```bash
forge test -vvv
```

## Networks

The project is configured with the following test networks:

| Network | Purpose |
|---|---|
| Ethereum Sepolia | Source network |
| Arbitrum Sepolia | Destination network |

Cross-chain functionality uses Chainlink CCIP and requires the appropriate router, token pool, remote-chain configuration, and token administration setup on both networks.

## Learning Outcomes

Through this project, I explored and implemented several important smart contract development concepts:

- Advanced Solidity programming.
- ERC-20 token customization.
- Interest accrual and dynamic balance calculations.
- Inheritance and interface implementation.
- Access control and ownership management.
- Cross-chain interoperability using Chainlink CCIP.
- Token burning and minting across blockchain networks.
- Foundry unit and integration testing.
- Fork testing and local CCIP simulation.
- Smart contract deployment and configuration across multiple networks.

## Acknowledgements

- [Cyfrin Updraft](https://updraft.cyfrin.io/) – Advanced Foundry course and project guidance.
- [Chainlink](https://chain.link/) – Cross-Chain Interoperability Protocol.
- [Foundry](https://getfoundry.sh/) – Smart contract development toolkit.
- [OpenZeppelin](https://www.openzeppelin.com/) – Secure and reusable smart contract libraries.

## Author

**Yashesh Kumar**

- GitHub: [@KYashesh](https://github.com/KYashesh)
- LinkedIn: [Yashesh Kumar](https://www.linkedin.com/in/yashesh-kumar-8b1bbb256/)

---

*This project was developed as part of my journey in Solidity and smart contract development, with a focus on DeFi mechanisms and cross-chain interoperability.*
