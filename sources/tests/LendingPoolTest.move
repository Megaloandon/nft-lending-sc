module lending_addr::lending_pool_test {
    use std::signer;
    use std::debug::print;
    use std::string;
    use std::vector;
    use lending_addr::lending_pool;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use lending_addr::mega_coin::{Self, MegaAPT};
    use lending_addr::digital_asset;

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
        let deposit_amount = 1000000000;
        lending_pool::deposit<FakeAPT>(user, deposit_amount);
    }
    
    #[test_only]
    fun test_init(admin: &signer, user1: &signer) acquires FreeCoins {
        let admin_addr = signer::address_of(admin);
        let user1_addr = signer::address_of(user1);
        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user1_addr);
        coin::register<MegaAPT>(admin);
        coin::register<MegaAPT>(user1);
        // admin add to pool
        init_fake_pools(admin);
        lending_pool::admin_add_pool_for_test<FakeAPT>(admin);
        coin::register<FakeAPT>(admin);
        let free_coins = borrow_global_mut<FreeCoins>(admin_addr);
        let admin_deposit_amount: u256 = 1000000000000;
        let apt = coin::extract(&mut free_coins.apt_coin, (admin_deposit_amount as u64));
        coin::deposit<FakeAPT>(admin_addr, apt);
        lending_pool::deposit<FakeAPT>(admin, admin_deposit_amount);

        // user deposit to pool
        create_fake_user(user1);
        digital_asset::create_collection(
            string::utf8(b"Description"),
            7777,
            string::utf8(COLLECTION_NAME_TEST),
            string::utf8(b"Uri"),
        );
    }

    #[test_only]
    public fun set_up_test_for_time(aptos_framework: &signer) {
        // set up global time for testing purpose
        timestamp::set_time_has_started_for_testing(aptos_framework);
    }

    #[test (aptos_framework = @aptos_framework)]
    public fun test_timestamp(
        aptos_framework: &signer
    ) {
        set_up_test_for_time(aptos_framework);
        let now = timestamp::now_seconds();
        timestamp::update_global_time_for_test_secs(now + 10);
        let now = timestamp::now_seconds();
        assert!(now == 10, ERR_TEST);
    }

    #[test(admin=@lending_addr, user1=@0x1001, aptos_framework = @aptos_framework)]
    public fun test_deposit(admin: &signer, user1: &signer, aptos_framework: &signer) acquires FreeCoins {
        let admin_addr = signer::address_of(admin);
        let user1_addr = signer::address_of(user1);
        set_up_test_for_time(aptos_framework);
        lending_pool::init_module_for_tests(admin);
        test_init(admin, user1);
        let (total_deposit, deposit_apy, borrow_apy) = lending_pool::get_market_configuration();
        assert!(total_deposit == 1001000000000, ERR_TEST);

        let admin_balance = coin::balance<FakeAPT>(admin_addr);
        let user_balance = coin::balance<FakeAPT>(user1_addr);
        assert!(admin_balance == 0, ERR_TEST);
        assert!(user_balance == 0, ERR_TEST);

        let lender_list = lending_pool::get_all_user_deposit();
        let lender_numbers = vector::length(&lender_list);
        let i = 0;
        while (i < lender_numbers) {
            let lender_address = vector::borrow(&lender_list, (i as u64));
            // print(lender_address);
            i = i + 1;
        };

        let (user1_deposit, accumulated_amount) = lending_pool::get_lender_information(user1_addr);
        // print(&user1_deposit);
        assert!(user1_deposit == 1000000000, ERR_TEST);
    }       

    #[test(admin=@lending_addr, user1=@0x1001, aptos_framework = @aptos_framework)]
    public fun test_withdraw(admin: &signer, user1: &signer, aptos_framework: &signer) acquires FreeCoins {
        let admin_addr = signer::address_of(admin);
        let user1_addr = signer::address_of(user1);
        set_up_test_for_time(aptos_framework);
        
        // admin deposits 1.000.000 * 10^6 
        // user deposits 1.000 * 10^6
        lending_pool::init_module_for_tests(admin);
        test_init(admin, user1);

        let user1_mega_balance = coin::balance<MegaAPT>(user1_addr);
        assert!(user1_mega_balance == user1_mega_balance, ERR_TEST);

        // after 1 year = 31536000 second
        // 1.000.000 * 5.82% APY
        let now = timestamp::now_seconds();
        timestamp::update_global_time_for_test_secs(now + 31536000);
        let one_year_later = timestamp::now_seconds();
        assert!(one_year_later == 31536000, ERR_TEST);

        // before withdraw
        let (user1_deposit_amount, accumulated_amount) = lending_pool::get_lender_information(user1_addr);
        assert!(user1_deposit_amount == 1000000000, ERR_TEST);
        assert!(accumulated_amount == 1000000000, ERR_TEST);
        let user1_balance = coin::balance<FakeAPT>(user1_addr);
        assert!(user1_balance == 0, ERR_TEST);
        let user1_mega_balance = coin::balance<MegaAPT>(user1_addr);
        assert!(user1_mega_balance == 1000000000, ERR_TEST);
        // after withdraw
        lending_pool::withdraw<FakeAPT>(user1, accumulated_amount);
        let user1_balance = coin::balance<FakeAPT>(user1_addr);
        assert!(user1_balance == 1000000000, ERR_TEST);
        let user1_mega_balance = coin::balance<MegaAPT>(user1_addr);
        assert!(user1_mega_balance == 0, ERR_TEST);
        let (user1_deposit_amount, accumulated_amount) = lending_pool::get_lender_information(user1_addr);
        assert!(user1_deposit_amount == 0, ERR_TEST);
        assert!(accumulated_amount == 0, ERR_TEST);
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

    #[test(admin=@lending_addr, user1=@0x1001, aptos_framework = @aptos_framework)]
    public fun test_deposit_collateral(admin: &signer, user1: &signer, aptos_framework: &signer) acquires FreeCoins {
        let admin_addr = signer::address_of(admin);
        let user1_addr = signer::address_of(user1);
        set_up_test_for_time(aptos_framework);
        
        // admin deposits 1.000.000 * 10^6 
        // user deposits 1.000 * 10^6
        lending_pool::init_module_for_tests(admin);
        test_init(admin, user1);

        // create nft for user1 
        create_nft(user1_addr, 329);
        create_nft(user1_addr, 98);
        create_nft(user1_addr, 174);

        // deposit nft to lending pool
        lending_pool::deposit_collateral(user1, string::utf8(COLLECTION_NAME_TEST), 329);
        lending_pool::deposit_collateral(user1, string::utf8(COLLECTION_NAME_TEST), 98);
        lending_pool::deposit_collateral(user1, string::utf8(COLLECTION_NAME_TEST), 174);
        // let current_owner = digital_asset::get_owner_token(329);
        // assert!(current_owner == @lending_addr, ERR_TEST);

        let (borrow_amount, repaid_amount, total_collateral_amount, health_factor, available_to_borrow) = lending_pool::get_borrower_information(user1_addr);
        assert!(total_collateral_amount == 3 * 3499000, ERR_TEST);

        // digital_asset::transfer_token(329, user1_addr);
        // let current_owner = digital_asset::get_owner_token(329);
        // assert!(current_owner == user1_addr, ERR_TEST);
    }

    #[test(admin=@lending_addr, user1=@0x1001, aptos_framework = @aptos_framework)]
    public fun test_deposit_multi_collateral(admin: &signer, user1: &signer, aptos_framework: &signer) acquires FreeCoins {
        let admin_addr = signer::address_of(admin);
        let user1_addr = signer::address_of(user1);
        set_up_test_for_time(aptos_framework);
        
        // admin deposits 1.000.000 * 10^6 
        // user deposits 1.000 * 10^6
        lending_pool::init_module_for_tests(admin);
        test_init(admin, user1);

        // create nft for user1 
        create_nft(user1_addr, 329);
        create_nft(user1_addr, 98);
        create_nft(user1_addr, 174);

        let collateral_list = vector::empty();
        let first_collateral = string::utf8(b"Collection Test#329");
        vector::push_back(&mut collateral_list, first_collateral);
        let second_collateral = string::utf8(b"Collection Test#98");
        vector::push_back(&mut collateral_list, second_collateral);
        let third_collateral = string::utf8(b"Collection Test#174");
        vector::push_back(&mut collateral_list, third_collateral);

        // deposit nft to lending pool
        lending_pool::deposit_multi_collateral(user1, collateral_list);
        // let current_owner = digital_asset::get_owner_token(329);
        // assert!(current_owner == @lending_addr, ERR_TEST);

        let (borrow_amount, repaid_amount, total_collateral_amount, health_factor, available_to_borrow) = lending_pool::get_borrower_information(user1_addr);
        assert!(total_collateral_amount == 3 * 3499000, ERR_TEST);

        // digital_asset::transfer_token(329, user1_addr);
        // let current_owner = digital_asset::get_owner_token(329);
        // assert!(current_owner == user1_addr, ERR_TEST);
    }

    #[test(admin=@lending_addr, user1=@0x1001, aptos_framework = @aptos_framework)]
    public fun test_borrow(admin: &signer, user1: &signer, aptos_framework: &signer) acquires FreeCoins {
        let admin_addr = signer::address_of(admin);
        let user1_addr = signer::address_of(user1);
        test_deposit_collateral(admin, user1, aptos_framework);
        let (borrow_amount, repaid_amount, total_collateral_amount, health_factor, available_to_borrow) = lending_pool::get_borrower_information(user1_addr);
        assert!(available_to_borrow == 6298200, ERR_TEST);
        assert!(health_factor == 0, ERR_TEST);

        // borrow 5 APT
        lending_pool::borrow<FakeAPT>(user1, 5000000);
        let (borrow_amount, repaid_amount, total_collateral_amount, health_factor, available_to_borrow) = lending_pool::get_borrower_information(user1_addr);
        assert!(borrow_amount == 5000000, ERR_TEST);
        assert!(repaid_amount == 0, ERR_TEST);
        assert!(total_collateral_amount == 3 * 3499000, ERR_TEST);
        assert!(health_factor == 1784490, ERR_TEST);
        assert!(available_to_borrow == 1298200, ERR_TEST);
        let user_balance = coin::balance<FakeAPT>(user1_addr);
        assert!(user_balance == 5000000, ERR_TEST);
    }

     #[test(admin=@lending_addr, user1=@0x1001, aptos_framework = @aptos_framework)]
    public fun test_repay(admin: &signer, user1: &signer, aptos_framework: &signer) acquires FreeCoins {
        let admin_addr = signer::address_of(admin);
        let user1_addr = signer::address_of(user1);
        test_borrow(admin, user1, aptos_framework);
        
        // after repay part of debt
        lending_pool::repay<FakeAPT>(user1, 2000000);
        let addr = digital_asset::get_owner_token(string::utf8(COLLECTION_NAME_TEST), 329);
        assert!(addr != user1_addr, ERR_TEST);
        let addr = digital_asset::get_owner_token(string::utf8(COLLECTION_NAME_TEST), 98);
        assert!(addr != user1_addr, ERR_TEST);
        let addr = digital_asset::get_owner_token(string::utf8(COLLECTION_NAME_TEST), 174);
        assert!(addr != user1_addr, ERR_TEST);
        let (borrow_amount, repaid_amount, total_collateral_amount, health_factor, available_to_borrow) = lending_pool::get_borrower_information(user1_addr);
        assert!(borrow_amount == 3000000, ERR_TEST);
        assert!(repaid_amount == 2000000, ERR_TEST);
        assert!(total_collateral_amount == 3 * 3499000, ERR_TEST);
        assert!(health_factor == 2974150, ERR_TEST);
        assert!(available_to_borrow == 3298200, ERR_TEST);
        let user1_balance = coin::balance<FakeAPT>(user1_addr);
        assert!(user1_balance == 3000000, ERR_TEST);

        // after repay all debt
        lending_pool::repay<FakeAPT>(user1, 3000000);
        let addr = digital_asset::get_owner_token(string::utf8(COLLECTION_NAME_TEST), 329);
        assert!(addr == user1_addr, ERR_TEST);
        let addr = digital_asset::get_owner_token(string::utf8(COLLECTION_NAME_TEST), 98);
        assert!(addr == user1_addr, ERR_TEST);
        let addr = digital_asset::get_owner_token(string::utf8(COLLECTION_NAME_TEST), 174);
        assert!(addr == user1_addr, ERR_TEST);
        let (borrow_amount, repaid_amount, total_collateral_amount, health_factor, available_to_borrow) = lending_pool::get_borrower_information(user1_addr);
        assert!(borrow_amount == 0, ERR_TEST);
        assert!(repaid_amount == 0, ERR_TEST);
        assert!(total_collateral_amount == 0, ERR_TEST);
        assert!(health_factor == 0, ERR_TEST);
        assert!(available_to_borrow == 0, ERR_TEST);
        let user1_balance = coin::balance<FakeAPT>(user1_addr);
        assert!(user1_balance == 0, ERR_TEST);
    }

}