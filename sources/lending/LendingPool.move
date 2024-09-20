module lending_addr::lending_pool {  
    use std::debug::print; 
    use std::vector;
    use std::string::{Self, String};  
    use std::signer;
    use std::simple_map::{Self, SimpleMap};
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::object;
    use lending_addr::mega_coin::{Self, MockAPT, MegaAPT};
    use lending_addr::digital_asset;
    use lending_addr::mock_oracle;
    use lending_addr::mock_flash_loan;

    const YEAR_TO_SECOND: u256 = 31536000;
    const BASE: u256 = 1000000;
    const ERR_INSUCCIENTFUL: u64 = 1000;
    const INITIAL_COIN: u256 = 1000000000000;

    friend lending_addr::exchange;

    struct MarketReserve<phantom CoinType> has key {
        reserve: Coin<CoinType>
    }

    // store lending information of each lender
    struct Lender has key, store, drop {
        deposit_amount: u256,
        lasted_update_time: u64,
    }

    struct Collateral has key, store, drop, copy {
        collection_name: String,
        token_id: u64,
    }

    // store loan information of each borrower
    struct Borrower has key, store, copy, drop {
        borrow_amount: u256,
        repaid_amount: u256,
        total_collateral_amount: u256,
        lasted_update_time: u64,
        health_factor: u256,
        available_to_borrow: u256,
        collateral_list: vector<Collateral>,
        collateral_map: SimpleMap<u64, NFT>,
    }

    // store information of each NFT
    struct NFT has key, store, copy, drop {
        price: u256,
        ltv: u256,
        liquidation_threshold: u256,
    }

    // store configuration of each market
    struct Market has key, store, drop {
        total_deposit: u256,
        deposit_apy: u256,
        borrow_apy: u256,
        lender_list: vector<address>, // list of all lenders
        lender_map: SimpleMap<address, Lender>,
        borrower_list: vector<address>, // list of all borrowers
        borrower_map: SimpleMap<address, Borrower>,
    }

    // automatically called when deploy this module 
    fun init_module(sender: &signer) {
        move_to(sender, Market {
            total_deposit: 0,
            deposit_apy: 58200,
            borrow_apy: 94600,
            lender_list: vector::empty(),
            lender_map: simple_map::create(),
            borrower_list: vector::empty(),
            borrower_map: simple_map::create(),
        });
        mega_coin::initialize(sender);
        digital_asset::initialize(sender);
        move_to<MarketReserve<MockAPT>>(sender, MarketReserve<MockAPT> {
            reserve: coin::zero<MockAPT>(),
        });
    }

    // ===================================================================================
    // ================================= Entry Function ==================================
    // ===================================================================================

    public entry fun create_reserve<CoinType>() acquires Market, MarketReserve {
        let creator_constructor_ref = &object::create_object(@lending_addr);
        let creator_extend_ref = object::generate_extend_ref(creator_constructor_ref);
        let creator = &object::generate_signer_for_extending(&creator_extend_ref);
        account::create_account_if_does_not_exist(signer::address_of(creator));
        coin::register<CoinType>(creator);
        coin::register<MegaAPT>(creator);
        mega_coin::mint<CoinType>(creator, 2 * (INITIAL_COIN as u64));
        deposit<CoinType>(creator, INITIAL_COIN);
        mock_flash_loan::deposit<CoinType>(creator, INITIAL_COIN);
    }

    public entry fun deposit<CoinType>(sender: &signer, amount: u256) acquires Market, MarketReserve {
        let sender_addr = signer::address_of(sender);
        let market = borrow_global_mut<Market>(@lending_addr);

        // update pool total deposited
        market.total_deposit = market.total_deposit + amount;

        // withdraw from user wallet
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let coin = coin::withdraw<CoinType>(sender, (amount as u64));
        coin::merge(reserve, coin);
        
        // update lender storage
        let lender_list = &mut market.lender_list;
        let lender_map = &mut market.lender_map;
        let is_sender_exists = vector::contains(lender_list, &sender_addr);
        let now = timestamp::now_seconds();
        if(is_sender_exists) {
            let lender = simple_map::borrow_mut<address, Lender>(lender_map, &sender_addr);
            lender.deposit_amount = lender.deposit_amount + amount;
            lender.lasted_update_time = now;
        } else {
            let lender = Lender {
                deposit_amount: amount,
                lasted_update_time: now,
            };
            vector::push_back(lender_list, sender_addr);
            simple_map::add(lender_map, sender_addr, lender)
        };

        // mint mAPT for user 
        mega_coin::mint<MegaAPT>(sender, (amount as u64));
    }

    public entry fun withdraw<CoinType>(sender: &signer, amount: u256) acquires Market, MarketReserve {
        let sender_addr = signer::address_of(sender);
        let market = borrow_global_mut<Market>(@lending_addr);
        let lender_map = &mut market.lender_map;
        let lender = simple_map::borrow_mut<address, Lender>(lender_map, &sender_addr);

        // check if deposited amount of user less than amount to withdraw
        // print(&lender.deposit_amount);
        // print(&amount);

        // get enough mAPTs from user
        mega_coin::withdraw<MegaAPT>(sender, (lender.deposit_amount as u64));

        // update_lending_accumulated(lender, market.deposit_apy);

        // deposit coin to user wallet
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let coin = coin::extract(reserve, (amount as u64));
        coin::deposit(sender_addr, coin);

        // update pool total deposited
        market.total_deposit = market.total_deposit - amount;
        lender.deposit_amount = lender.deposit_amount - amount;
        lender.lasted_update_time = timestamp::now_seconds();
    }

    public entry fun deposit_collateral(sender: &signer, collection_name: String, token_id: u64) acquires Market {
        let sender_addr = signer::address_of(sender);
        let market = borrow_global_mut<Market>(@lending_addr);
        let borrower_list = &mut market.borrower_list;
        let borrower_map = &mut market.borrower_map;
        let borrower_numbers = vector::length(borrower_list);
        let is_borrower_exist = vector::contains(borrower_list, &sender_addr);
        let nft = get_nft_configuration(token_id);
        let new_available_to_borrow = nft.price * nft.ltv / BASE;
        // get NFT from user wallet and transfer debt NFT to user wallet
        digital_asset::withdraw_token(sender, collection_name, token_id);
        digital_asset::transfer_debt_token(sender_addr, collection_name, token_id);
        
        // update borrower storage
        if(is_borrower_exist) {
            let borrower = simple_map::borrow_mut<address, Borrower>(borrower_map, &sender_addr);
            borrower.total_collateral_amount = borrower.total_collateral_amount + nft.price;
            borrower.lasted_update_time = timestamp::now_seconds();
            let new_health_factor = 0;
            if (borrower.borrow_amount != 0) {
                new_health_factor = nft.price * nft.liquidation_threshold / borrower.borrow_amount;
            };
            borrower.health_factor = borrower.health_factor + new_health_factor;
            borrower.available_to_borrow = borrower.available_to_borrow + new_available_to_borrow;
            let collateral_map = &mut borrower.collateral_map;
            let collateral_list = &mut borrower.collateral_list;
            simple_map::add(collateral_map, token_id, nft);
            let collateral = Collateral {
                collection_name,
                token_id,
            };
            vector::push_back(collateral_list, collateral);
        } else {
            let new_collateral_map: SimpleMap<u64, NFT> = simple_map::create();
            let collateral_amount = nft.price;
            simple_map::add(&mut new_collateral_map, token_id, nft);
            let new_collateral_list: vector<Collateral> = vector::empty();
            let collateral = Collateral {
                collection_name,
                token_id,
            };
            vector::push_back(&mut new_collateral_list, collateral);
            let borrower = Borrower {
                borrow_amount: 0,
                repaid_amount: 0,
                total_collateral_amount: collateral_amount,
                lasted_update_time: timestamp::now_seconds(),
                health_factor: 0,
                available_to_borrow: new_available_to_borrow,
                collateral_list: new_collateral_list,
                collateral_map: new_collateral_map,
            };
            vector::push_back(borrower_list, sender_addr);
            simple_map::add(borrower_map, sender_addr, borrower);
        };
    }

    public entry fun borrow<CoinType>(sender: &signer, amount: u256) acquires Market, MarketReserve {
        let sender_addr = signer::address_of(sender);
        let market = borrow_global_mut<Market>(@lending_addr);
        let borrower_list = &mut market.borrower_list;
        let borrower_map = &mut market.borrower_map;
        let borrower = simple_map::borrow_mut<address, Borrower>(borrower_map, &sender_addr);
        // check amount <= available to borrow
        assert!(amount <= borrower.available_to_borrow, ERR_INSUCCIENTFUL);

        // send APT to user
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let coin = coin::extract(reserve, (amount as u64));
        coin::deposit(sender_addr, coin);

        // update to storage
        market.total_deposit = market.total_deposit - amount;
        borrower.borrow_amount = borrower.borrow_amount + amount;
        borrower.lasted_update_time = timestamp::now_seconds();
        // recalculate health factor & available to borrow
        let collateral_list = &borrower.collateral_list;
        let collateral_map = &borrower.collateral_map;
        let collateral_numbers = vector::length(collateral_list);
        let i = 0;
        let hf_without_debt = 0;
        while (i < collateral_numbers) {
            let collateral = vector::borrow(collateral_list, (i as u64));
            let token_id = collateral.token_id;
            let nft = simple_map::borrow<u64, NFT>(collateral_map, &token_id);
            hf_without_debt = hf_without_debt + nft.price * nft.liquidation_threshold;
            i = i + 1;
        };
        let health_factor = hf_without_debt / borrower.borrow_amount;
        borrower.health_factor = health_factor;
        borrower.available_to_borrow = borrower.available_to_borrow - amount;
    }

    public entry fun repay<CoinType>(sender: &signer, collection_name: String, amount: u256) acquires Market, MarketReserve {
        let sender_addr = signer::address_of(sender);
        let market = borrow_global_mut<Market>(@lending_addr);
        let borrower_list = &mut market.borrower_list;
        let borrower_map = &mut market.borrower_map;
        let borrower = simple_map::borrow_mut<address, Borrower>(borrower_map, &sender_addr);

        // user deposit APT to pool
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let coin = coin::withdraw<CoinType>(sender, (amount as u64));
        coin::merge(reserve, coin);

        // update borrower storage
        // print(&signer::address_of(sender));
        // print(&amount);
        // print(&borrower.borrow_amount);
        borrower.borrow_amount = borrower.borrow_amount - amount;
        borrower.repaid_amount = borrower.repaid_amount + amount;
        borrower.lasted_update_time = timestamp::now_seconds();
        // recalculate health factor & available to borrow
        let collateral_list = &mut borrower.collateral_list;
        let collateral_map = &mut borrower.collateral_map;
        let collateral_numbers = vector::length(collateral_list);
        let i = 0;
        let hf_without_debt = 0;
        while (i < collateral_numbers) {
            let collateral = vector::borrow(collateral_list, (i as u64));
            let token_id = collateral.token_id;
            let nft = simple_map::borrow<u64, NFT>(collateral_map, &token_id);
            hf_without_debt = hf_without_debt + nft.price * nft.liquidation_threshold;
            i = i + 1;
        };
        if(borrower.borrow_amount != 0) {
            borrower.health_factor = hf_without_debt / borrower.borrow_amount;
            borrower.available_to_borrow = borrower.available_to_borrow + amount;
        } else {
            // if borrow_amount = 0 then transfer NFT for user 
            borrower.health_factor = 0;
            borrower.repaid_amount = 0;
            borrower.total_collateral_amount = 0;
            borrower.lasted_update_time = timestamp::now_seconds();
            borrower.available_to_borrow = 0;
            let collateral_numbers = vector::length(collateral_list);
            let i = collateral_numbers - 1;
            while(i >= 0) {
                let collateral = vector::borrow(collateral_list, (i as u64));
                let token_id = collateral.token_id;
                // transfer NFT to user wallet and get debt NFT form user wallet
                digital_asset::transfer_token(sender_addr, collection_name, token_id);
                digital_asset::withdraw_debt_token(sender, collection_name, token_id);
                vector::remove(collateral_list, (i as u64));
                simple_map::remove(collateral_map, &token_id);
                if(i == 0) {
                    break;
                } else {
                    i = i - 1;
                };
            };
        };
        
        
    }

    // ===================================================================================
    // ================================= Helper Function =================================
    // ===================================================================================

    public fun get_nft_configuration(token_id: u64): NFT {
        let price = mock_oracle::get_full_payment_price(token_id);
        let nft = NFT {
            price: price,
            ltv: 600000,
            liquidation_threshold: 850000,
        };
        nft
    }

    public fun update_lending_accumulated(lender: &mut Lender, deposit_apy: u256) {
        let now = timestamp::now_seconds();
        let desired_amount: u256 = lender.deposit_amount * deposit_apy; // desired amount after 1 year
        let delta_time = now - lender.lasted_update_time;
        if(delta_time == 0) {
            return;
        };

        let amount_accumulated = desired_amount * (delta_time as u256) / YEAR_TO_SECOND;
        amount_accumulated = amount_accumulated / BASE;
        lender.deposit_amount = lender.deposit_amount + amount_accumulated;
        lender.lasted_update_time = now;
    }

    // =================================================================================
    // ================================= View Function =================================
    // =================================================================================

    #[view]
    public fun get_all_user_deposit(): vector<address> acquires Market {
        let lender_list = borrow_global<Market>(@lending_addr).lender_list;
        lender_list
    }
    #[view]
    public fun get_lender_information(user_addr: address): (u256, u256) acquires Market {
        let market = borrow_global_mut<Market>(@lending_addr);
        let lender_map = &mut market.lender_map;
        let lender = simple_map::borrow_mut<address, Lender>(lender_map, &user_addr);
        // update_lending_accumulated(lender, market.deposit_apy);
        (lender.deposit_amount, lender.deposit_amount)
    }

    #[view]
    public fun get_market_configuration(): (u256, u256, u256) acquires Market {
        let market = borrow_global<Market>(@lending_addr);
        (market.total_deposit, market.deposit_apy, market.borrow_apy)
    }

    #[view]
    public fun get_collateral_numbers(user_addr: address): u64 acquires Market {
        let market = borrow_global_mut<Market>(@lending_addr);
        let borrower_map = &mut market.borrower_map;
        let borrower = simple_map::borrow_mut<address, Borrower>(borrower_map, &user_addr);
        let collateral_list = &borrower.collateral_list;
        let collateral_numbers = vector::length(collateral_list);
        collateral_numbers
    }

    #[view]
    public fun get_collateral(user_addr: address, collateral_id: u64): (String, u64) acquires Market {
        let market = borrow_global_mut<Market>(@lending_addr);
        let borrower_map = &mut market.borrower_map;
        let borrower = simple_map::borrow_mut<address, Borrower>(borrower_map, &user_addr);
        let collateral_list = &borrower.collateral_list;
        let collateral = vector::borrow(collateral_list, collateral_id);
        (collateral.collection_name, collateral.token_id)
    }

    #[view]
    public fun get_borrower_information(user_addr: address): (u256, u256, u256, u256, u256) acquires Market {
        let market = borrow_global_mut<Market>(@lending_addr);
        let borrower_map = &mut market.borrower_map;
        let borrower = simple_map::borrow_mut<address, Borrower>(borrower_map, &user_addr);
        (borrower.borrow_amount, borrower.repaid_amount, borrower.total_collateral_amount, borrower.health_factor, borrower.available_to_borrow)
    }

    // ================================ Test Function ====================================

    #[test_only]
    public fun init_module_for_tests(sender: &signer) {
        init_module(sender);
    }

    #[test_only]
    public fun admin_add_pool_for_test<CoinType>(sender: &signer) {
        move_to<MarketReserve<CoinType>>(sender, MarketReserve<CoinType> {
            reserve: coin::zero<CoinType>(),
        });
    }
}

