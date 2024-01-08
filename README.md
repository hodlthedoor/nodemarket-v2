```
 /$$   /$$  /$$$$$$  /$$$$$$$  /$$$$$$$$       /$$      /$$  /$$$$$$  /$$$$$$$  /$$   /$$ /$$$$$$$$ /$$$$$$$$
| $$$ | $$ /$$__  $$| $$__  $$| $$_____/      | $$$    /$$$ /$$__  $$| $$__  $$| $$  /$$/| $$_____/|__  $$__/
| $$$$| $$| $$  \ $$| $$  \ $$| $$            | $$$$  /$$$$| $$  \ $$| $$  \ $$| $$ /$$/ | $$         | $$   
| $$ $$ $$| $$  | $$| $$  | $$| $$$$$         | $$ $$/$$ $$| $$$$$$$$| $$$$$$$/| $$$$$/  | $$$$$      | $$   
| $$  $$$$| $$  | $$| $$  | $$| $$__/         | $$  $$$| $$| $$__  $$| $$__  $$| $$  $$  | $$__/      | $$   
| $$\  $$$| $$  | $$| $$  | $$| $$            | $$\  $ | $$| $$  | $$| $$  \ $$| $$\  $$ | $$         | $$   
| $$ \  $$|  $$$$$$/| $$$$$$$/| $$$$$$$$      | $$ \/  | $$| $$  | $$| $$  | $$| $$ \  $$| $$$$$$$$   | $$   
|__/  \__/ \______/ |_______/ |________/      |__/     |__/|__/  |__/|__/  |__/|__/  \__/|________/   |__/  
```

# OTC Exchange V2 Smart Contract

## Overview
OTC Exchange V2 is a smart contract for Over-The-Counter (OTC) trading of tokens on Ethereum. It allows users to create and fill orders for buying and selling tokens directly with each other. The contract supports both ERC20 tokens and Ethereum (ETH) trades.

## Features
- **Order Creation and Cancellation**: Users can create buy or sell orders specifying the amount, price, and other order details. Orders can be cancelled by the creator before they are filled.
- **Order Filling**: Orders can be filled by other users, with checks in place to ensure order validity and signer authorization.
- **Commission Handling**: The contract charges a commission on trades, configurable by the contract administrator.
- **Role-Based Access Control**: Utilizes OpenZeppelin's AccessControl for managing roles like withdrawers and token administrators.
- **Signature Verification**: Ensures the authenticity of orders through a two-tiered signature verification process. Each order is signed by the maker to confirm its details and additionally by a trusted gateway, preventing front-running. This dual-signature approach, involving both the maker and an approved entity, guarantees the integrity of every transaction and protects against potential manipulations like front-running.

## Usage

### Roles
- **DEFAULT_ADMIN_ROLE**: Full control over the contract, able to set commission rates and addresses.
- **WITHDRAWER_ROLE**: Authorized to withdraw funds from the contract.
- **TOKEN_ADMIN_ROLE**: Can update the list of valid payment and sale tokens.

### Functions

#### Public
- `fillOrder(...)`: Fill a valid order.
- `createOrder(...)`: Create a new order.
- `cancelOrder(...)`: Cancel an existing order.
- `cancelMultipleOrders(...)`: Cancel multiple orders at once.
- `incrementNonce(...)`: Increment a user's nonce to invalidate old orders.
- `incrementPairNonce(...)`: Increment a trading pair's nonce.
- `getCommission(...)`: Calculate the commission for an order.
- `owner()`: Returns the owner of the contract. Used for setting primary ENS owner.

#### Admin-Only
- `setCommission(...)`: Set the commission rate.
- `setCommissionAddress(...)`: Set the address to receive commission.
- `updateSigner(...)`: Approve or disapprove a signer.
- `updateEnsOwner(...)`: Update the owner for ENS purposes.


#### Role-Based
- `withdraw(...)`: Withdraw ETH from the contract.
- `withdrawToken(...)`: Withdraw ERC20 tokens from the contract.
- `updatePaymentToken(...)`: Approve or disapprove a payment token.
- `updateSaleToken(...)`: Approve or disapprove a sale token.

### Events
- `UpdateSigner`
- `OnchainBuyOrderCreated`
- `OrderFilled`
- `OrderCancelled`
- `NonceIncremented`
- `PairNonceIncremented`

## Installation
1. Run tests with Foundry: `forge test` (https://book.getfoundry.sh/)

## Testing
Comprehensive tests are provided in the `test/OtcExchange_V2Test.sol` file. These tests cover various scenarios including order creation, filling, cancellation, and nonce management.

## Author
- hodl.esf.eth

## License
This project is licensed under the MIT License.

