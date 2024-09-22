module lending_addr::auction_test {
    use std::signer;
    use std::debug::print;
    use std::string;
    use std::vector;
    use lending_addr::mega_coin::{Self, MegaAPT};
    use lending_addr::digital_asset;
    use lending_addr::english_auction;
    use lending_addr::lending_pool;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::account;
    use aptos_framework::timestamp;

    const ERR_TEST: u64 = 1000;
    const COLLECTION_NAME_TEST: vector<u8> = b"Collection Test";

    struct FakeAPT {}

    struct FreeCoins has key {
        apt_coin: Coin<FakeAPT>,
        apt_cap: coin::MintCapability<FakeAPT>,
        apt_burn: coin::BurnCapability<FakeAPT>,
        apt_freeze: coin::FreezeCapability<FakeAPT>,
    }

    public fun init_fake_pools(admin: &signer) {
        let name = string::utf8(b"Aptos Token");
        let symbol = string::utf8(b"APT");
        let (apt_burn, apt_freeze, apt_cap) = coin::initialize<FakeAPT>(admin, name, symbol, 6, false);

        let mint_amount = 9000000000000;
        move_to(admin, FreeCoins {
            apt_coin: coin::mint<FakeAPT>(mint_amount, &apt_cap),
            apt_cap,
            apt_burn,
            apt_freeze,
        });
    }

    fun init_coin_stores(user: &signer) acquires FreeCoins {
        coin::register<FakeAPT>(user);
        let faucet_amount = 1000000000;
        let free_coins = borrow_global_mut<FreeCoins>(@lending_addr);
        let apt = coin::extract(&mut free_coins.apt_coin, faucet_amount);
        let addr = signer::address_of(user);
        coin::deposit(addr, apt);
    }

    public fun create_fake_user(user: &signer) acquires FreeCoins {
        init_coin_stores(user);
        // let deposit_amount = 1000000000;
        // lending_pool::deposit<FakeAPT>(user, deposit_amount);
    }

    #[test_only]
    public fun set_up_test_for_time(aptos_framework: &signer) {
        // set up global time for testing purpose
        timestamp::set_time_has_started_for_testing(aptos_framework);
    }

    #[test_only]
    fun test_init(admin: &signer, user1: &signer, user2: &signer, user3: &signer) acquires FreeCoins {
        let admin_addr = signer::address_of(admin);
        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);
        let user3_addr = signer::address_of(user3);
        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user1_addr);
        account::create_account_for_test(user2_addr);
        account::create_account_for_test(user3_addr);
        coin::register<MegaAPT>(admin);
        coin::register<MegaAPT>(user1);
        // admin add to pool
        init_fake_pools(admin);
        english_auction::init_module_for_tests(admin);
        coin::register<FakeAPT>(admin);
        let free_coins = borrow_global_mut<FreeCoins>(admin_addr);
        let admin_deposit_amount: u256 = 1000000000000;
        let apt = coin::extract(&mut free_coins.apt_coin, (2 * admin_deposit_amount as u64));
        coin::deposit<FakeAPT>(admin_addr, apt);

        create_fake_user(user1);
        create_fake_user(user2);
        create_fake_user(user3);
        digital_asset::create_collection(
            string::utf8(b"Description"),
            7777,
            string::utf8(COLLECTION_NAME_TEST),
            string::utf8(b"Uri"),
        )
    }
    
    #[test_only]
    public fun create_nft(owner_addr: address, token_id: u64) {
        digital_asset::mint_token(
            owner_addr,
            string::utf8(COLLECTION_NAME_TEST),
            token_id,
            string::utf8(b"AptosMonkeys"),
            string::utf8(b"Aptos Monkeys"),
            string::utf8(b"Test Uri"),
        );
    }

    #[test(admin = @lending_addr, user1 = @0x1001, user2 = @0x1002, user3 = @0x1003, aptos_framework = @aptos_framework)]
    public fun test_english_auction(
        admin: &signer, 
        user1: &signer, 
        user2: &signer, 
        user3: &signer,
        aptos_framework: &signer
    ) acquires FreeCoins {
        let admin_addr = signer::address_of(admin);
        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);
        let user3_addr = signer::address_of(user3);
        // set up test
        set_up_test_for_time(aptos_framework);
        lending_pool::init_module_for_tests(admin);
        test_init(admin, user1, user2, user3);
        english_auction::admin_add_pool_for_test<FakeAPT>(admin);

        // mint nft for user1
        create_nft(user1_addr, 329);
        create_nft(user1_addr, 98);
        create_nft(user1_addr, 174);
        
        english_auction::add_nft_to_auction(user1_addr, string::utf8(COLLECTION_NAME_TEST), 329, 2769000);
        english_auction::add_nft_to_auction(user1_addr, string::utf8(COLLECTION_NAME_TEST), 98, 1582000);

        let numbers_nft_to_aution = english_auction::get_numbers_nft_to_auction();
        assert!(numbers_nft_to_aution == 2, ERR_TEST);

        let (collection_name, token_id) = english_auction::get_nft_to_auction(0);
        assert!(token_id == 329, ERR_TEST);
        let (collection_name, token_id) = english_auction::get_nft_to_auction(1);
        assert!(token_id == 98, ERR_TEST);
        let is_first_bid = english_auction::check_if_first_bid(string::utf8(COLLECTION_NAME_TEST), 329);
        assert!(is_first_bid == true, ERR_TEST);
        let minimum_first_bid = english_auction::get_minimum_first_bid(string::utf8(COLLECTION_NAME_TEST), 329);
        assert!(minimum_first_bid == 2769000, ERR_TEST);
        english_auction::initialize_with_bid<FakeAPT>(user2, string::utf8(COLLECTION_NAME_TEST), 329, 2769001);
        let minimum_bid = english_auction::get_minimum_bid(string::utf8(COLLECTION_NAME_TEST), 329);
        assert!(minimum_bid == 2796691, ERR_TEST);

        english_auction::place_bid<FakeAPT>(user3, string::utf8(COLLECTION_NAME_TEST), 329, 3000000);
        let user3_balance = coin::balance<FakeAPT>(user3_addr);
        assert!(user3_balance == 997000000, ERR_TEST);

        let (
            current_debt,
            first_bid_addr,
            first_bid_amount,
            current_bid_addr,
            current_bid_amount,
            winner_addr,
            winner_amount
        ) = english_auction::get_bid_information(string::utf8(COLLECTION_NAME_TEST), 329);

        assert!(current_debt == 2769000, ERR_TEST);
        assert!(first_bid_addr == user2_addr, ERR_TEST);
        assert!(first_bid_amount == 2769001, ERR_TEST);
        assert!(current_bid_addr == user3_addr, ERR_TEST);
        assert!(current_bid_amount == 3000000, ERR_TEST);
    }
}