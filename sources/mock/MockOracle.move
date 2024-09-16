module lending_addr::mock_oracle {
    friend lending_addr::lending_pool;
    friend lending_addr::exchange;

    public fun get_floor_price(token_id: u64): u256 {
        let price = 3499000;
        price
    }

    public fun get_full_payment_price(token_id: u64): u256 {
        let price = 21800000;
        price
    }

    public fun get_down_payment_price(token_id: u64): u256 {
        let full_payment_price = get_full_payment_price(token_id);
        let down_payment_price = full_payment_price * 40 / 100;
        down_payment_price
    }
}