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

    const ERR_TEST: u64 = 1000;

    struct FakeAPT {}

    struct FreeCoins has key {
        apt_coin: Coin<FakeAPT>,
        apt_cap: coin::MintCapability<FakeAPT>,
        apt_burn: coin::BurnCapability<FakeAPT>,
        apt_freeze: coin::FreezeCapability<FakeAPT>,
    }

    public entry fun init_fake_pools(admin: &signer) {
        let admin_addr = signer::address_of(admin);
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

    public entry fun create_fake_user(user: &signer) acquires FreeCoins {
        init_coin_stores(user);
        let deposit_amount = 1000000000;
        lending_pool::deposit<FakeAPT>(user, 1000000000);
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
        lending_pool::admin_add_pool<FakeAPT>(admin);
        coin::register<FakeAPT>(admin);
        let free_coins = borrow_global_mut<FreeCoins>(admin_addr);
        let admin_deposit_amount: u256 = 1000000000000;
        let apt = coin::extract(&mut free_coins.apt_coin, (admin_deposit_amount as u64));
        coin::deposit<FakeAPT>(admin_addr, apt);
        lending_pool::deposit<FakeAPT>(admin, admin_deposit_amount);

        // user deposit to pool
        create_fake_user(user1);
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
            print(lender_address);
            i = i + 1;
        };

        let user1_deposit = lending_pool::get_deposit_amount_lender(user1_addr);
        print(&user1_deposit);
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

        let user1_deposit_amount = lending_pool::get_deposit_amount_lender(user1_addr);
        assert!(user1_deposit_amount == 1000000000, ERR_TEST);
        let user1_balance = coin::balance<FakeAPT>(user1_addr);
        assert!(user1_balance == 0, ERR_TEST);
        lending_pool::withdraw<FakeAPT>(user1, user1_deposit_amount);
        let user1_balance = coin::balance<FakeAPT>(user1_addr);
        assert!(user1_balance == 1058200000, ERR_TEST);
        let user1_current_amount = lending_pool::get_deposit_amount_lender(user1_addr);
        assert!(user1_current_amount == 0, ERR_TEST);
    }       
}