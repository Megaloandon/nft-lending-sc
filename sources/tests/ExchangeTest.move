module lending_addr::exchange_test {
    use std::signer;
    use std::debug::print;
    use std::string;
    use std::vector;
    use lending_addr::exchange;
    use lending_addr::mega_coin::{Self, MegaAPT};
    use lending_addr::digital_asset;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use lending_addr::lending_pool;

    const ERR_TEST: u64 = 1000;

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

        let mint_amount = 2000000000000;
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
        exchange::admin_add_pool_for_test<FakeAPT>(admin);
        coin::register<FakeAPT>(admin);
        let free_coins = borrow_global_mut<FreeCoins>(admin_addr);
        let admin_deposit_amount: u256 = 1000000000000;
        let apt = coin::extract(&mut free_coins.apt_coin, (admin_deposit_amount as u64));
        coin::deposit<FakeAPT>(admin_addr, apt);

        create_fake_user(user1);
        create_fake_user(user2);
        create_fake_user(user3);
    }
    
    #[test_only]
    public fun create_nft(owner_addr: address, token_id: u64) {
        digital_asset::mint_token(
            owner_addr,
            token_id,
            string::utf8(b"AptosMonkeys"),
            string::utf8(b"Aptos Monkeys"),
            string::utf8(b"Test Uri"),
        );
    }

    #[test(admin = @lending_addr, user1 = @0x1001, user2 = @0x1002, user3 = @0x1003, aptos_framework = @aptos_framework)]
    public fun test_offer_nft(
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
        exchange::init_module_for_tests(admin);
        test_init(admin, user1, user2, user3);

        // mint nft for user1
        create_nft(user1_addr, 329);
        create_nft(user1_addr, 98);
        create_nft(user1_addr, 174);

        // list offer NFT
        exchange::list_offer_nft(user1, 329);
        exchange::list_offer_nft(user1, 98);
        exchange::list_offer_nft(user1, 174);

        let offer_nft_list = exchange::get_all_offer_nft();
        let numbers = vector::length(&offer_nft_list);
        assert!(numbers == 3, ERR_TEST);
        let token_id_0 = *vector::borrow(&offer_nft_list, 0);
        let token_id_1 = *vector::borrow(&offer_nft_list, 1);
        let token_id_2 = *vector::borrow(&offer_nft_list, 2);
        assert!(token_id_0 == 329, ERR_TEST);
        assert!(token_id_1 == 98, ERR_TEST);
        assert!(token_id_2 == 174, ERR_TEST);
        let owner_token_id_2 = digital_asset::get_owner_token(98);
        assert!(owner_token_id_2 != user1_addr, ERR_TEST);
        // cancle list offer NFT 98
        exchange::cancle_list_offer_nft(user1_addr, 98);
        let offer_nft_list = exchange::get_all_offer_nft();
        let numbers = vector::length(&offer_nft_list);
        assert!(numbers == 2, ERR_TEST);
        let owner_token_id_2 = digital_asset::get_owner_token(98);
        assert!(owner_token_id_2 == user1_addr, ERR_TEST);

        // user2 make offer
        let user2_balance = coin::balance<FakeAPT>(user2_addr);
        assert!(user2_balance == 1000000000, ERR_TEST);
        exchange::add_offer<FakeAPT>(user2, 329, 5120000, 0);
        let user2_balance = coin::balance<FakeAPT>(user2_addr);
        assert!(user2_balance == 1000000000 - 5120000, ERR_TEST);

        // user3 make offer
        exchange::add_offer<FakeAPT>(user3, 329, 5310000, 0);

        let number_offers = exchange::get_number_offers(329);
        assert!(number_offers == 2, ERR_TEST);
        let (user_offer_address, offer_price, offer_time) = exchange::get_offer(329, 1);
        assert!(user_offer_address == user3_addr, ERR_TEST);
        assert!(offer_price == 5310000, ERR_TEST);

        // user3 cancel offer
        exchange::remove_offer<FakeAPT>(user3_addr, 329);
        let number_offers = exchange::get_number_offers(329);
        assert!(number_offers == 1, ERR_TEST);
        let (user_offer_address, offer_price, offer_time) = exchange::get_offer(329, 0);
        assert!(user_offer_address == user2_addr, ERR_TEST);
        assert!(offer_price == 5120000, ERR_TEST);
        
        // seller sell for offer's user2
        exchange::sell_offer_nft<FakeAPT>(user2_addr, 329);
    }
    
}