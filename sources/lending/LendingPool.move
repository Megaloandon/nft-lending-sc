module lending_addr::lending_pool {   
    use std::vector;
    use std::string::{Self, String};  
    use std::signer;
    use std::simple_map::{Self, SimpleMap};
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};

    friend lending_addr::digital_asset_minter;

    struct MarketReserve<phantom CoinType> has key {
        reserve: Coin<CoinType>
    }

    // store lending information of each lender
    struct Lender has key, store, drop {
        amount: u64,
        lasted_update_time: u64,
    }

    // store loan information of each borrower
    struct Borrower has key, store, drop {
        amount: u64,
        lasted_update_time: u64,
        health_factor: u64,
        collateral_list: SimpleMap<address, NFT>,
    }

    // store information of each NFT
    struct NFT has key, store, drop {
        floor_price: u64,
        ltv: u64,
        liquidation_threshold: u64,
        liquidation_price: u64,
    }

    // store configuration of each market
    struct Market has key, store, drop {
        total_deposit: u64,
        deposit_apy: u64,
        borrow_apy: u64,
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
    }

    // ===================================================================================
    // ================================= Entry Function ==================================
    // ===================================================================================

    public entry fun admin_add_pool<CoinType>(sender: &signer) {
        move_to<MarketReserve<CoinType>>(sender, MarketReserve<CoinType> {
            reserve: coin::zero<CoinType>(),
        });
    }

    public entry fun deposit<CoinType>(sender: &signer, amount: u64) acquires Market, MarketReserve {
        let sender_addr = signer::address_of(sender);
        let market = borrow_global_mut<Market>(@lending_addr);

        // update pool total deposited
        market.total_deposit = market.total_deposit + amount;

        // withdraw from user wallet
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let coin = coin::withdraw<CoinType>(sender, amount);
        coin::merge(reserve, coin);
        
        // update lending list & map
        let lending_list = &mut market.lender_list;
        let lending_map = &mut market.lender_map;
        let is_sender_exists = vector::contains(lending_list, &sender_addr);
        let now = timestamp::now_seconds();
        if(is_sender_exists) {
            let lending = simple_map::borrow_mut<address, Lender>(lending_map, &sender_addr);
            let amount_accumulated = get_amount_accumulated(lending.amount, lending.lasted_update_time, now);
            lending.amount = amount_accumulated;
            lending.amount = lending.amount + amount;
            lending.lasted_update_time = now;

        } else {
            let lender = Lender {
                amount: amount,
                lasted_update_time: now,
            };
            vector::push_back(lending_list, sender_addr);
            simple_map::add(lending_map, sender_addr, lender)
        }
    }

    // @todo
    public entry fun withdraw() {
        
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


    // @todo
    public fun get_amount_accumulated(amount: u64, lasted_update_time: u64, now: u64): u64 {
        amount
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
    public fun get_user_deposit_amount(user_addr: address): u64 acquires Market {
        let lender_map = &borrow_global<Market>(@lending_addr).lender_map;
        let lender = simple_map::borrow<address, Lender>(lender_map, &user_addr);
        lender.amount
    }

    #[view]
    public fun get_market_configuration(): (u64, u64, u64) acquires Market {
        let market = borrow_global<Market>(@lending_addr);
        (market.total_deposit, market.deposit_apy, market.borrow_apy)
    }

    #[test_only]
    public fun init_module_for_tests(sender: &signer) {
        init_module(sender);
    }
}

