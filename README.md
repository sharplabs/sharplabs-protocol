# Sharplabs Finance Protocol

This repository contains the smart contracts source code and markets configuration for Sharplabs Finance Protocol V1. The repository uses Hardhat as development environment for compilation, testing and deployment tasks.

## What is Sharplabs Finance?

Sharp Labs is a one-stop liquidity-as-a-Service (LaaS) provider. Our Delta Neutral Vault is a set of smart contracts that allow users to pool funds for liquidity providing on established DeFi protocols, such as GMX, in a delta-neutral manner. This vault capitalizes on high-frequency trading strategies, delta hedging and impermanent loss minimization, while earning rewards and transaction fees from providing liquidity to DeFi exchanges.

## Documentation

See the link to the white paper 

- [White Paper](https://sharplabs.finance/doc/)

## Audits 

You can find all audit reports here

V1 - MAY 2023

- [Certik](./audit/REP-final-20230508T031115Z.pdf)


## Connect with the community

[Discord channel](https://discord.gg/NdFQSFxPtc)

[Telegram](https://t.me/SharpLabsOfficial) 

[Twitter](https://twitter.com/sharp_labs?s=21&t=UiJQds_02kyBFnNJ-dXqfQ)

## Test

You can run the full test scripts with the following commands:

```
yarn install

yarn build

yarn test test/userTest.ts
```
