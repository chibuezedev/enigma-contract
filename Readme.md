# Enigma CDP

A privacy-preserving collateralized debt position protocol built on Starknet. Users deposit wBTC as collateral and borrow stablecoins against it. Position details are hidden on-chain using Pedersen hash commitments native to Cairo and Starknet's cryptographic stack.

## How It Works

When a user deposits collateral, the vault records the amount and stores a Pedersen commitment of the position rather than the raw values. Borrowing is gated by a 150% minimum collateral ratio. Liquidation is only possible below a 120% threshold. Liquidators cannot preemptively target positions based on exact collateral amounts.

The frontend masks position data behind hidden characters by default. Users reveal their own position on demand.

## Architecture

```
Frontend (Next.js)  ->  Backend API (Express)  ->  Starknet RPC  ->  Cairo Contract
```

## Contract Addresses (Starknet Sepolia)

| Contract | Address |
|---|---|
| CDPVault | 0x076ec52e0501e98457b89957357de94f5956b274db7a0df113533ae00b1a3ae8 |
| Mock wBTC | 0x026ec2c25324b8faa54bea72a3e60d61d6f1b56d87e50a19c9c1a5961dea73ef |
| Mock USDC | 0x04a9378f966341cf7a367ff0eef47da3381dcf686d0a0fc57acbc8aa241d2b9c |

## Tech Stack

- Cairo 2.16 (Starknet smart contract)
- Starknet Sepolia testnet
- Node.js / Express (backend API)
- Next.js (frontend)
- starknet.js 7.6.4
- Braavos wallet

## Contract Parameters

- Minimum collateral ratio: 150%
- Liquidation threshold: 120%
- Liquidation bonus: 10%
- Collateral decimals: 8 (wBTC)
- Debt decimals: 18 (USDC)

## Privacy Mechanism

Each position stores a Pedersen commitment on-chain:

```
commitment = pedersen(collateral_low, debt_low)
```

The raw collateral and debt values are stored in contract storage but are not emitted or exposed in a way that reveals the position to observers without access to the owner's data. The commitment is updated on every position change and emitted as an event, allowing the owner to verify their position off-chain.

## Running Locally

Clone the repository and set up both the backend and frontend.

**Backend**

```bash
cd backend
npm install
cp .env.example .env
# Fill in your values in .env
npm start
```

**Frontend**

```bash
cd frontend
npm install
cp .env.local.example .env.local
# Set NEXT_PUBLIC_API_URL=http://localhost:3001
npm run dev
```

## Environment Variables

Backend `.env`:

```
RPC_URL=https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_8/YOUR_KEY
ACCOUNT_ADDRESS=your_deployer_address
PRIVATE_KEY=your_private_key
VAULT_ADDRESS=0x076ec52e0501e98457b89957357de94f5956b274db7a0df113533ae00b1a3ae8
COLLATERAL_TOKEN_ADDRESS=0x026ec2c25324b8faa54bea72a3e60d61d6f1b56d87e50a19c9c1a5961dea73ef
DEBT_TOKEN_ADDRESS=0x04a9378f966341cf7a367ff0eef47da3381dcf686d0a0fc57acbc8aa241d2b9c
PORT=3001
```

Frontend `.env.local`:

```
NEXT_PUBLIC_API_URL=http://localhost:3001
```

## API Endpoints

| Method | Route | Description |
|---|---|---|
| GET | /price | Get current BTC price from contract |
| POST | /price | Update BTC price (owner only) |
| GET | /position/:address | Get position for address |
| POST | /deposit | Deposit wBTC collateral |
| POST | /borrow | Borrow USDC against collateral |
| POST | /repay | Repay outstanding debt |
| POST | /withdraw | Withdraw collateral |
| POST | /liquidate | Liquidate undercollateralized position |
| POST | /approve/collateral | Approve vault to spend wBTC |
| POST | /approve/debt | Approve vault to spend USDC for repay |
| POST | /mint/collateral | Mint test wBTC (testnet only) |
| POST | /mint/debt | Mint test USDC (testnet only) |

## Building the Contract

Requires Scarb 2.16.0 and sncast 0.57.0 via starkup.

```bash
cd contract
scarb build
```

To declare and deploy:

```bash
sncast --account your_account declare --contract-name CDPVault
sncast --account your_account deploy --class-hash YOUR_CLASS_HASH \
  --arguments 'owner, collateral_token, debt_token, initial_btc_price'
```

## Hackathon

Built for the Re{define} Hackathon — Bitcoin and Privacy on Starknet, February 2026.