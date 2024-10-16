# Introduction

`Aptos` is a **next-generation Layer 1** blockchain designed to enhance the scalability, security, and user experience of decentralized applications. In our `Megaloandon` protocol, `Aptos` plays a critical role by providing a **fast** and **secure** environment for transactions and smart contracts. For NFT Lending, `Aptos` ensures real-time liquidation and collateral management, allowing users to leverage their NFTs as collateral to borrow assets and trading of NFTs with **lower gas fees** and **faster finality** compared to traditional blockchains. By using `Aptos'` advanced architecture, the platform ensures that transactions remain decentralized, secure, and efficient, empowering users to **maximize** the liquidity of their NFT assets with **minimal** risk

# Core Contract

- **Lending Contracts**: Relating to lending and borrowing operations, for lenders and borrowers.

- **Exchange Contracts**: A marketplace that connects buyers, and sellers, and includes unique features like down payment and collateral listing.

- **Auction Contracts**: Automate the auction process if a borrower's health factor drops below 1, ensuring transparency and fairness in liquidation events.

- **Oracle Contracts**: Oracle contracts gather data from various NFT marketplaces and use algorithms to calculate a final price for NFTs, ensuring objectivity and fairness.

# Testnet Deployment
**Lending protocols**
```bash
0x498afaeb1ae2ff1d077516cb588ad9adaff60c04b577904cfd0d3cfe58c98eef
```

**Megaloandon Oracle**
```bash
0x9ecc4f0af6934c425dfd8c83f34cc8895bc1b82bd1b3adccfdb416ecff697675
```

# Compile

```bash
aptos move compile
```

# Test

```bash
aptos move test
```

# Add as dependency

Add to `Move.toml`

```toml
[dependencies.nft-lending]
git = "https://github.com/Megaloandon/nft-lending-sc.git"
rev = "<commit hash>"
```
And then use in code:

```rust
use lending_addr::lending_pool;
...
lending_pool::deposit
```

# LICENSE
MIT.
