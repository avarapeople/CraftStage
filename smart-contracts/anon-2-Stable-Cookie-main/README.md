# 🍪 Stable Cookie 🍪

Are you concerned about insane inflation rates? Introducing our groundbreaking solution that brings stability to the world! 🌍💰

## About the Project 🚀
The inflation is huge, but worry not! With StableCookie, we've baked up a solution: Cookies that always stay fresh at $1 each. 🍪💰

StableCookie is a fully decentralized, algorithmic, and exogenously collateralized stablecoin pegged to the dollar. Here's how it works:

## Smart Contract Architecture 🏛️

### DAO (Decentralized Autonomous Organization)

Our DAO ensures the project's smooth operation, introducing two key contracts:

- **GovernorContract**: The heart of the DAO, this contract manages crucial functions such as proposing, executing, and more. It empowers our community members to voice their opinions and add new token as collateral to the StableCookie.

- **TimeLock**: An contract designed to maintain a secure proposal and execution timeframe. It oversees the process, ensuring proposals follow the proper governance channels before being executed. Additionally, it holds the ownership of the CookieStore, no one can add a new collateral but this contract.

- **GovernanceToken**: GovernanceToken allows community members to vote for adding or not a new token collateral.

### Stablecoin 
- **StableCoookie**: Representing the essence of our project, StableCoookie is the ERC20 token that embodies the stability of our endeavor. It provides users with a reliable anchor in the sea of volatile cryptocurrencies.

- **CookieStore**: CookieStore, the logic that keeps our cookies' price stable, serves as the backbone of our stablecoin system. It's the driving force that maintains equilibrium, fostering trust and confidence among our users.

## Requirements 🛠️

To experience the magic of the Decentralized Cookie Project, you'll need the following tools:

- [Git](https://git-scm.com/): Version control to keep things organized and collaborative.
- [Node.js](https://nodejs.org/): JavaScript runtime environment for executing code.
- [Yarn](https://classic.yarnpkg.com/): Package manager to handle dependencies seamlessly.
- [Slither](https://github.com/crytic/slither): Auditing tool.

## Deploying the Contracts 🌐

Brace yourself to dive into the world of stable cookies! Deploying the contracts is as easy as pie (or should we say cookies?):

1. Make sure you have Git, Node.js, and Yarn installed.
2. Clone this repository using Git.
3. Execute `yarn` to install the dependecies.
4. Create a `.env` file, copy `.env.example` in it and complete it.
5. Navigate to the project directory.
6. Execute `yarn hardhat compile` to compile the contracts.
7. Execute `yarn hardhat deploy` to deploy the contracts.
8. Execute `yarn hardhat docgen` to have the documentation.
9. Execute `slither .` to audit the smart contracts.

Please note that there might be a minor hiccup during CookieStore deployment.

Join us in revolutionizing stability in the crypto realm, one cookie at a time! 🍪🌟

For inquiries and support, don't hesitate to connect with us.

Stay stable, stay sweet! 🍀🍪
