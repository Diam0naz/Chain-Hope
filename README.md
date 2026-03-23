# ChainHope — Transparent Charity on StarkNet

A decentralized charity platform built on StarkNet/Cairo where donations go directly to verified recipients with full on-chain transparency.

## Features
- Community governance voting on charity requests
- Direct ERC20 donations to verified recipients
- Reentrancy protection
- Two step ownership transfer
- Token whitelist
- Timelock on governance changes
- Pause mechanism

## Contract
- **Network:** StarkNet Sepolia
- **Address:** `0x0413a8ca2ebade8635f590fdc86074b34e811e2fe638bb0cd9ded41a004c6d25`
- **Class Hash:** `0x2c52601aa3ab1064505694001c55370cb4c4a89bd0a34eb5826c8c41f5899f`

## Tech Stack
- Cairo 2.16.0
- Scarb 2.16.0
- OpenZeppelin Cairo Contracts
- Starknet Foundry 0.57.0

## Setup
```bash
# Install dependencies
scarb fetch

# Build
scarb build

# Test
snforge test

# Deploy
sncast --profile sepolia declare --contract-name ChainHope
sncast --profile sepolia deploy --class-hash <CLASS_HASH> --arguments <OWNER>,<THRESHOLD>,<TOKEN>
```

## Test Results
```
Tests: 40 passed, 0 failed
```
