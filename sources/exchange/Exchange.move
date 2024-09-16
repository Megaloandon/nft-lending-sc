module lending_addr::exchange {
    use std::signer;
    use lending_addr::storage;
    use lending_addr::digital_asset;
    use lending_addr::mock_oracle;
    use lending_addr::mega_coin;
    use lending_addr::lending_pool;

    friend lending_addr::exchange_test;

    //============================================================================
    //=============================== Entry Fucntion =============================
    //============================================================================
    
    public entry fun list_offer_nft(sender: &signer, token_id: u64) {
        digital_asset::withdraw_token(sender, token_id);
        storage::add_offer_nft(token_id, signer::address_of(sender));
    }

    public entry fun cancle_list_offer_nft(sender: &signer, token_id: u64) {
        digital_asset::transfer_token(sender, token_id);
        storage::remove_offer_nft(token_id);
    }

    public entry fun list_instantly_nft<CoinType>(sender: &signer, token_id: u64) {
        let nft_price = mock_oracle::get_floor_price(token_id);
        let instantly_amount = nft_price * 60 / 100;
        lending_pool::deposit_collateral(sender, token_id);
        lending_pool::borrow<CoinType>(sender, instantly_amount);

        storage::add_instantly_nft(token_id, signer::address_of(sender)); 
    }

    public entry fun add_offer(sender_addr: address, token_id: u64, offer_price: u256, offer_time: u256) {
        storage::user_add_offer(sender_addr, token_id, offer_price, offer_time);
    }

    public entry fun remove_offer(sender_addr: address, token_id: u64) {
        storage::user_remove_offer(sender_addr, token_id);
    }

    public entry fun sell_offer_nft<CoinType>(sender: &signer, token_id: u64, offer_owner: address) {
        let (offer_price, offer_time) = storage::get_offer_information(token_id, offer_owner);
        let nft_owner_addr = storage::get_nft_owner_addr(token_id);
        mega_coin::withdraw<CoinType>(sender, (offer_price as u64));
        mega_coin::mint<CoinType>(nft_owner_addr, (offer_price as u64));
        storage::remove_offer_nft(token_id);
    }

    public entry fun sell_instantly_nft<CoinType>(sender: &signer, token_id: u64) {
        let nft_price = mock_oracle::get_floor_price(token_id);
        let amount_to_repay = nft_price * 60 / 100;
        lending_pool::repay<CoinType>(sender, amount_to_repay);
        let remaining_amount = nft_price - amount_to_repay;
        let nft_owner_addr = storage::get_nft_owner_addr(token_id);
        mega_coin::transfer<CoinType>(sender, nft_owner_addr, (remaining_amount as u64));
        digital_asset::transfer_token(sender, token_id);
        storage::remove_instantly_nft(token_id);
    }

    //===========================================================================
    //=============================== View Fucntion =============================
    //===========================================================================

    #[view]
    public fun get_all_offer_nft(): vector<u64> {
        let offer_nft = storage::get_all_offer_nft();
        offer_nft
    }

    #[view]
    public fun get_all_instantly_nft(): vector<u64> {
        let instantly_nft = storage::get_all_instantly_nft();
        instantly_nft
    }

    #[view]
    public fun get_number_offers(token_id: u64): u64 {
        let number_offers = storage::get_number_offers(token_id);
        number_offers
    }

    #[view]
    public fun get_offer(token_id: u64, offer_id: u64): (address, u256, u256) {
        let (user_offer_address, offer_price, offer_time) = storage::get_offer(token_id, offer_id);
        (user_offer_address, offer_price, offer_time)
    }

    #[view]
    public fun get_nft_price(token_id: u64): (u256, u256, u256) {
        let floor_price = mock_oracle::get_floor_price(token_id);
        let full_payment_price = mock_oracle::get_full_payment_price(token_id);
        let down_payment_price = mock_oracle::get_down_payment_price(token_id);
        (floor_price, full_payment_price, down_payment_price)
    }

    #[test_only]
    public fun init_module_for_tests(sender: &signer) {
        storage::init_module_for_tests(sender);
    }
}