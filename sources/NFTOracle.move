module lending_addr::nft_oracle {
    use std::string::{Self, String};
    friend lending_addr::lending_pool;
    friend lending_addr::exchange;
    use oracle_addr::oracle;

    public entry fun request_price_data(collection_name: String, token_id: u64, floor_price: u256, full_payment_price: u256) {
        oracle::request_price_data(@lending_addr, collection_name, token_id, floor_price, full_payment_price)
    }

    #[view]
    public fun get_floor_price(collection_name: String, token_id: u64): u256 {
        let price = oracle::get_floor_price(@lending_addr, collection_name, token_id);
        price
    }

    #[view]
    public fun get_full_payment_price(collection_name: String, token_id: u64): u256 {
        let price = oracle::get_full_payment_price(@lending_addr, collection_name, token_id);
        price
    }

    #[view]
    public fun get_down_payment_price(collection_name: String, token_id: u64): u256 {
        let price = oracle::get_down_payment_price(@lending_addr, collection_name, token_id);
        price
    }
}