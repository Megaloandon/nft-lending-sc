# Core Contract

- **Lending Contracts**: Relating to lending and borrowing operations, for lenders and borrowers.

- **Exchange Contracts**: A marketplace that connects buyers, and sellers, and includes unique features like down payment and collateral listing.

- **Auction Contracts**: Automate the auction process if a borrower's health factor drops below 1, ensuring transparency and fairness in liquidation events.

- **Oracle Contracts**: Oracle contracts gather data from various NFT marketplaces and use algorithms to calculate a final price for NFTs, ensuring objectivity and fairness.

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
