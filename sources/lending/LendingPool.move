module lending_addr::lending_pool {  
    use std::debug::print; 
    use std::vector;
    use std::string::{Self, String};  
    use std::signer;
    use std::simple_map::{Self, SimpleMap};
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};
    use lending_addr::mega_coin::{Self, MegaAPT};
    use lending_addr::digital_asset;

    const YEAR_TO_SECOND: u256 = 31536000;
    const BASE: u256 = 1000000;
    const ERR_INSUCCIENTFUL: u64 = 1000;


    struct MarketReserve<phantom CoinType> has key {
        reserve: Coin<CoinType>
    }

    // store lending information of each lender
    struct Lender has key, store, drop {
        deposit_amount: u256,
        accumulated_amount: u256,
        lasted_update_time: u64,
    }

    // store loan information of each borrower
    struct Borrower has key, store, drop {
        borrow_amount: u256,
        accumulated_amount: u256,
        total_collateral_amount: u256,
        lasted_update_time: u64,
        health_factor: u64,
        collateral_list: SimpleMap<u64, NFT>,
    }

    // store information of each NFT
    struct NFT has key, store, drop {
        floor_price: u256,
        ltv: u64,
        liquidation_threshold: u64,
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
    }

    // ===================================================================================
    // ================================= Entry Function ==================================
    // ===================================================================================

    public entry fun admin_add_pool<CoinType>(sender: &signer) {
        move_to<MarketReserve<CoinType>>(sender, MarketReserve<CoinType> {
            reserve: coin::zero<CoinType>(),
        });
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
            update_lending_accumulated(lender, market.deposit_apy);
            lender.deposit_amount = lender.deposit_amount + amount;
            lender.accumulated_amount = lender.accumulated_amount + amount;
            lender.lasted_update_time = now;
        } else {
            let lender = Lender {
                deposit_amount: amount,
                accumulated_amount: amount,
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
        print(&lender.deposit_amount);
        print(&amount);
        assert!(lender.deposit_amount >= amount, ERR_INSUCCIENTFUL);

        // get enough mAPTs from user
        mega_coin::withdraw<MegaAPT>(sender, (amount as u64));

        update_lending_accumulated(lender, market.deposit_apy);

        // deposit coin to user wallet
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let accumulated_amount = lender.accumulated_amount;
        let coin = coin::extract(reserve, (accumulated_amount as u64));
        coin::deposit(sender_addr, coin);

        // update pool total deposited
        market.total_deposit = market.total_deposit - amount;
        lender.deposit_amount = lender.deposit_amount - amount;
        lender.accumulated_amount = lender.accumulated_amount - amount;
        lender.lasted_update_time = timestamp::now_seconds();
    }

    // 
    public entry fun deposit_collateral(sender: &signer, token_id: u64) acquires Market {
        let sender_addr = signer::address_of(sender);
        let market = borrow_global_mut<Market>(@lending_addr);
        let borrower_list = &mut market.borrower_list;
        let borrower_map = &mut market.borrower_map;
        let borrower_numbers = vector::length(borrower_list);
        let is_borrower_exist = vector::contains(borrower_list, &sender_addr);
        let nft = get_nft_configuration(token_id);

        // get NFT from user wallet
        digital_asset::transfer_token(sender, token_id, @lending_addr);
        
        // update borrower storage
        if(is_borrower_exist) {
            let borrower = simple_map::borrow_mut<address, Borrower>(borrower_map, &sender_addr);
            borrower.total_collateral_amount = borrower.total_collateral_amount + nft.floor_price;
            borrower.lasted_update_time = timestamp::now_seconds();
            borrower.health_factor = calculate_health_factor();
            let collateral_list = &mut borrower.collateral_list;
            simple_map::add(collateral_list, token_id, nft);
        } else {
            let new_collateral_list: SimpleMap<u64, NFT> = simple_map::create();
            let collateral_amount = nft.floor_price;
            simple_map::add(&mut new_collateral_list, token_id, nft);
            let borrower = Borrower {
                borrow_amount: 0,
                accumulated_amount: 0,
                total_collateral_amount: collateral_amount,
                lasted_update_time: timestamp::now_seconds(),
                health_factor: 0,
                collateral_list: new_collateral_list,
            };
            vector::push_back(borrower_list, sender_addr);
            simple_map::add(borrower_map, sender_addr, borrower);
        }
    }

    // @todo
    public entry fun borrow() {
        
    }


    // @todo
    public entry fun repay() {

    }

    // @todo
    public entry fun auction() {

    }

    // @todo
    public entry fun redeem() {

    }

    // @todo
    public entry fun liquidate() {

    }

    // ===================================================================================
    // ================================= Helper Function =================================
    // ===================================================================================

    public fun get_nft_configuration(token_id: u64): NFT {
        let nft = NFT {
            floor_price: 349900,
            ltv: 600000,
            liquidation_threshold: 850000,
        };
        nft
    }

    public fun calculate_health_factor(): u64 {
        0
    }

    // @todo
    public fun update_lending_accumulated(lender: &mut Lender, deposit_apy: u256) {
        let now = timestamp::now_seconds();
        let desired_amount: u256 = lender.accumulated_amount * deposit_apy; // desired amount after 1 year
        let delta_time = now - lender.lasted_update_time;
        if(delta_time == 0) {
            return;
        };

        let amount_accumulated = desired_amount * (delta_time as u256) / YEAR_TO_SECOND;
        amount_accumulated = amount_accumulated / BASE;
        lender.accumulated_amount = lender.accumulated_amount + amount_accumulated;
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
    public fun get_deposit_amount_lender(user_addr: address): u256 acquires Market {
        let market = borrow_global<Market>(@lending_addr);
        let lender_map = &market.lender_map;
        let lender = simple_map::borrow<address, Lender>(lender_map, &user_addr);
        lender.deposit_amount
    }

    #[view]
    public fun get_accumulated_amount_lender(user_addr: address): u256 acquires Market {
        let market = borrow_global_mut<Market>(@lending_addr);
        let lender_map = &mut market.lender_map;
        let lender = simple_map::borrow_mut<address, Lender>(lender_map, &user_addr);
        update_lending_accumulated(lender, market.deposit_apy);
        lender.accumulated_amount
    }


    #[view]
    public fun get_market_configuration(): (u256, u256, u256) acquires Market {
        let market = borrow_global<Market>(@lending_addr);
        (market.total_deposit, market.deposit_apy, market.borrow_apy)
    }

    #[test_only]
    public fun init_module_for_tests(sender: &signer) {
        init_module(sender);
    }
}

