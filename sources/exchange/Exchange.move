module lending_addr::exchange {
    use std::debug::print;
    use std::signer;
    use std::string::{Self, String};
    use lending_addr::storage;
    use lending_addr::digital_asset;
    use lending_addr::mock_oracle;
    use lending_addr::lending_pool;
    use lending_addr::mock_flash_loan;
    use std::simple_map::{Self, SimpleMap};
    use lending_addr::mega_coin::{Self, MockAPT};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::account;
    use aptos_framework::object::{Self, Object, ExtendRef};

    const ERR_INSUCIENTFUL_BALANCE: u64 = 1000;

    friend lending_addr::exchange_test;

    struct MarketReserve<phantom CoinType> has key {
        reserve: Coin<CoinType>
    }

    // creator represent for seller to borrow instantly 60% of each NFT
    struct ExchangeCreators has key {
        extend_ref_list: SimpleMap<u64, ExtendRef>,
    }

    // creator represent for buyer to make flash loan with Aries 
    struct FlashLoanCreators has key {
extend_ref_list: SimpleMap<u64, ExtendRef>,
    }

    fun init_module(sender: &signer) {
        move_to(sender, ExchangeCreators { 
            extend_ref_list: simple_map::create(),
        });

        move_to(sender, FlashLoanCreators {
            extend_ref_list: simple_map::create(),
        });

        move_to<MarketReserve<MockAPT>>(sender, MarketReserve<MockAPT> {
            reserve: coin::zero<MockAPT>(),
        });
    }

    //============================================================================
    //=============================== Entry Fucntion =============================
    //============================================================================
    
    // Seller list nft and wait for buyers
    public entry fun list_offer_nft(sender: &signer, collection_name: String, token_id: u64) {
        digital_asset::withdraw_token(sender, collection_name, token_id);
        storage::add_offer_nft(token_id, signer::address_of(sender));
    }

    // Seller cancel list nft
    public entry fun cancel_list_offer_nft(sender_addr: address, collection_name: String, token_id: u64) {
        digital_asset::transfer_token(sender_addr, collection_name, token_id);
        storage::remove_offer_nft(token_id);
    }


    // Seller list nft to instantly receive coin
    public entry fun list_instantly_nft<CoinType>(sender: &signer, collection_name: String, token_id: u64) acquires ExchangeCreators {
        let extend_ref_list = &mut borrow_global_mut<ExchangeCreators>(@lending_addr).extend_ref_list;
        // create creator has a role reprensentative for seller to borrow on pool and get instantly liquidity
        let creator_constructor_ref = &object::create_object(@lending_addr);
        let creator_extend_ref = object::generate_extend_ref(creator_constructor_ref);
        let creator = &object::generate_signer_for_extending(&creator_extend_ref);
        simple_map::add(extend_ref_list, token_id, creator_extend_ref);
        account::create_account_if_does_not_exist(signer::address_of(creator));
        coin::register<CoinType>(creator);
        
        let nft_price = mock_oracle::get_full_payment_price(token_id);
        let instantly_amount = nft_price * 60 / 100;

        // withdraw token from user wallet and deposit to creator of this contract, then creator will be borrower of lending pool
        digital_asset::withdraw_token(sender, collection_name, token_id);
        digital_asset::transfer_token(signer::address_of(creator), collection_name, token_id);
        lending_pool::deposit_collateral(creator, collection_name, token_id);
        lending_pool::borrow<CoinType>(creator, instantly_amount);   

        // withdraw coin from creator and deposit to sender address
        let coin = coin::withdraw<CoinType>(creator, (instantly_amount as u64));
        coin::deposit<CoinType>(signer::address_of(sender), coin);
        storage::add_instantly_nft(token_id, signer::address_of(sender)); 
    }

    // Buyer offer specify nft with offer price and offer time to buy nft
    public entry fun add_offer<CoinType>(sender: &signer, token_id: u64, offer_price: u256, offer_time: u256) acquires MarketReserve {
        let floor_price = mock_oracle::get_floor_price(token_id);
        assert!(offer_price >= floor_price, ERR_INSUCIENTFUL_BALANCE);
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let coin = coin::withdraw<CoinType>(sender, (offer_price as u64));
        coin::merge(reserve, coin);
        storage::user_add_offer(signer::address_of(sender), token_id, offer_price, offer_time);
    }


    // Buyer cancel offer
    public entry fun remove_offer<CoinType>(sender_addr: address, token_id: u64) acquires MarketReserve {
        let (offer_price, offer_time) = storage::get_offer_information(token_id,  sender_addr);
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let coin = coin::extract(reserve, (offer_price as u64));
        coin::deposit(sender_addr, coin);
        storage::user_remove_offer(sender_addr, token_id);
    }
    

    /*
        Seller sell nft which offerd by buyer(sender_addr)
        @params sender_addr: address of buyer who make offer
    */
    public entry fun sell_with_offer_nft<CoinType>(sender_addr: address, collection_name: String, token_id: u64) acquires MarketReserve {
        sell_offer_nft<CoinType>(sender_addr, collection_name, token_id);
    }

    // Buyer call this function to buy nft with full payment
    public entry fun buy_with_full_payment<CoinType>(sender: &signer, collection_name: String, token_id: u64) acquires MarketReserve, ExchangeCreators {
        sell_instantly_nft<CoinType>(sender, collection_name, token_id);
    }

    // Buyer call this function to buy nft with down payment
    public entry fun buy_with_down_payment<CoinType>(sender: &signer, collection_name: String, token_id: u64) acquires  MarketReserve, ExchangeCreators {
        // create creator has a role reprensentative for BUYER to make flash loan and borrow 60% full paymment price of NFT
        let creator_constructor_ref = &object::create_object(@lending_addr);
        let creator_extend_ref = object::generate_extend_ref(creator_constructor_ref);
        let creator = &object::generate_signer_for_extending(&creator_extend_ref);
        account::create_account_if_does_not_exist(signer::address_of(creator));
        coin::register<CoinType>(creator);

        let full_payment_price = mock_oracle::get_full_payment_price(token_id);
        let pre_payment = full_payment_price * 40 / 100;
        let coin = coin::withdraw<CoinType>(sender, (pre_payment as u64));
        coin::deposit<CoinType>(signer::address_of(creator), coin);
        // make flash loan and repay flash loan in one transaction
        let remaining_payment = full_payment_price - pre_payment;
        mock_flash_loan::flash_loan<CoinType>(creator, remaining_payment);
        // buy instantly nft which listed 
        sell_instantly_nft<CoinType>(creator, collection_name, token_id);
        // deposit NFT to owner who is represented for the Loan
        digital_asset::withdraw_token(creator, collection_name, token_id);
        digital_asset::transfer_token(signer::address_of(sender), collection_name, token_id);
        // list to exchange and instantly received 60% to repay flash loan
        list_instantly_nft<CoinType>(sender, collection_name, token_id);
        let coin = coin::withdraw<CoinType>(sender, (remaining_payment as u64));
        coin::deposit<CoinType>(signer::address_of(creator), coin);
        mock_flash_loan::repay_flash_loan<CoinType>(creator);
        // right now buyer is the borrower of lending protocol
    }

    //=============================================================================
    //=============================== Helper Fucntion =============================
    //=============================================================================

    fun sell_offer_nft<CoinType>(receiver_addr: address, collection_name: String, token_id: u64) acquires MarketReserve {
        let (offer_price, offer_time) = storage::get_offer_information(token_id,  receiver_addr);
        let nft_owner_addr = storage::get_nft_owner_addr(token_id);
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let coin = coin::extract(reserve, (offer_price as u64));
        coin::deposit(nft_owner_addr, coin);
        digital_asset::transfer_token(receiver_addr, collection_name, token_id);
        storage::remove_offer_nft(token_id);
    }

    fun sell_instantly_nft<CoinType>(sender: &signer, collection_name: String, token_id: u64) acquires MarketReserve, ExchangeCreators {
        let extend_ref_list = &mut borrow_global_mut<ExchangeCreators>(@lending_addr).extend_ref_list;
        let creator_extend_ref = simple_map::borrow<u64, ExtendRef>(extend_ref_list, &token_id);
        let creator = &object::generate_signer_for_extending(creator_extend_ref);
        let nft_price = mock_oracle::get_full_payment_price(token_id);

        // 60% used to repay debt of lending protocol
        let amount_to_repay = nft_price * 60 / 100;
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let coin = coin::withdraw<CoinType>(sender, (nft_price as u64));
        let coin_to_repay_debt = coin::extract(&mut coin, (amount_to_repay as u64));
        coin::deposit(signer::address_of(creator), coin_to_repay_debt);
        // creator of this contract repay debt on behalf of user, then receive NFT -> transfer to buyer
        lending_pool::repay<CoinType>(creator, amount_to_repay);
        
        // withdraw nft from creator and deposit to buyer
        // let (borrow_amount, repaid_amount, total_collateral_amount, health_factor, available_to_borrow) = lending_pool::get_borrower_information(signer::address_of(creator));  
        let owner = digital_asset::get_owner_token(collection_name, token_id);
        assert!(owner == signer::address_of(creator), 0);
        digital_asset::withdraw_token(creator, collection_name, token_id);
        digital_asset::transfer_token(signer::address_of(sender), collection_name, token_id);

        // 40% remaining deposit to owner of this NFT
        let remaining_amount = nft_price - amount_to_repay;
        let nft_owner_addr = storage::get_nft_owner_addr(token_id);
        coin::deposit(nft_owner_addr, coin); 
        storage::remove_instantly_nft(token_id);
        // remove creator of this NFT
        simple_map::remove(extend_ref_list, &token_id);
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

    //======================================= Test Function ==================================

    #[test_only]
    public fun init_module_for_tests(sender: &signer) {
        init_module(sender);
        storage::init_module_for_tests(sender);
        mock_flash_loan::init_module_for_tests(sender);
    }

    #[test_only]
    public fun admin_add_pool_for_test<CoinType>(sender: &signer) {
        move_to<MarketReserve<CoinType>>(sender, MarketReserve<CoinType> {
            reserve: coin::zero<CoinType>(),
        });
    }
}