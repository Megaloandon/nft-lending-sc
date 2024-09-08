module lending_addr::resources {
    use std::string::{Self, String};
    use std::simple_map::{Self, SimpleMap};
    use aptos_framework::timestamp;

    // store lending information of each lender
    struct Lending {
        amount: u64,
        lasted_update_time: u64,
    }

    // store loan information of each borrower
    struct Loan {
        amount: u64,
        lasted_update_time: u64,
        health_factor: u64,
        collateral_list: SimpleMap<address, NFT>,
    }

    // store information of each NFT
    struct NFT {
        floor_price: u64,
        ltv: u64,
        liquidation_threshold: u64,
        liquidation_price: u64,
    }

    // store configuration of each market
    struct Market {
        reserve: u64,
        lending_rate: u64,
        loan_rate: u64,
        ltv: u64,
        liquidation_threshold: u64,
        debt_token_name: String, // represent for name of debt token to track debt for borrower
        debt_token_symbol: String, 
        mega_token_name: String, // represent for name of megaloandon token to track lending for lender (similar to aToken of aave)
        mega_token_symbol: String,
        lendMap: SimpleMap<address, Lending>,
        loanMap: SimpleMap<address, Loan>,
    }

    // each market represented by String name of Token like APT, ETH, ...
    struct MarketMap {
        market_record: SimpleMap<String, Market>
    }
}