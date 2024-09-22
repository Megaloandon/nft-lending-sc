module lending_addr::english_auction {
    use std::vector;
    use std::signer;
    use std::string::{Self, String};
    use aptos_framework::coin::{Self, Coin};
    use lending_addr::mega_coin::{Self, MockAPT};
    use std::simple_map::{Self, SimpleMap};
    use lending_addr::digital_asset;
    use lending_addr::lending_pool;
    use aptos_framework::object::{Self, Object, ExtendRef};

    const WINNER: u64 = 1;
    const ERR_INSUFFICIENT_BALANCE: u64 = 2;

    struct MarketReserve<phantom CoinType> has key {
        reserve: Coin<CoinType>
    }
    
    struct BidRecord has key, store, drop {
        current_debt: u256,
        first_bid_addr: address,
        first_bid_amount: u256,
        current_bid_addr: address,
        current_bid_amount: u256,
        winner_addr: address,
        winner_amount: u256,
    }

    struct NFTToAuction has key, store, drop {
        collection_name: String,
        token_id: u64,
    }

    struct AuctionRecord has key {
        nft_to_auction_list: vector<NFTToAuction>,
        nft_to_auction_map: SimpleMap<NFTToAuction, BidRecord>,
    }

    fun init_moudule(sender: &signer) {
        move_to(sender, AuctionRecord {
            nft_to_auction_list: vector::empty(),
            nft_to_auction_map: simple_map::create(),
        });

        move_to<MarketReserve<MockAPT>>(sender, MarketReserve<MockAPT> {
            reserve: coin::zero<MockAPT>(),
        });
    }

    //=====================================================================================
    //================================ Entry Function =====================================
    //=====================================================================================

    public entry fun add_nft_to_auction(owner_addr: address, collection_name: String, token_id: u64, current_debt: u256) acquires AuctionRecord {
        let nft_to_auction_map = &mut borrow_global_mut<AuctionRecord>(@lending_addr).nft_to_auction_map;
        let nft_to_auction = NFTToAuction {
            collection_name,
            token_id,
        };
        let bid_record = BidRecord {
            current_debt,
            first_bid_addr: @0x0,
            first_bid_amount: 0,
            current_bid_addr: @0x0,
            current_bid_amount: 0,
            winner_addr: @0x0,
            winner_amount: 0,
        };
        simple_map::add(nft_to_auction_map, nft_to_auction, bid_record);
    }  

    public entry fun initialize_with_bid<CoinType>(sender: &signer, collection_name: String, token_id: u64, bid_amount: u256) acquires AuctionRecord, MarketReserve {
        let sender_addr = signer::address_of(sender);
        let nft_to_auction_map = &mut borrow_global_mut<AuctionRecord>(@lending_addr).nft_to_auction_map;
        let nft_to_auction = NFTToAuction {
            collection_name,
            token_id,
        };
        let bid_record = simple_map::borrow_mut<NFTToAuction, BidRecord>(nft_to_auction_map, &nft_to_auction);
        assert!(bid_amount >= bid_record.current_debt, ERR_INSUFFICIENT_BALANCE);

        bid_record.first_bid_addr = sender_addr;
        bid_record.first_bid_amount = bid_amount;
        bid_record.current_bid_addr = sender_addr;
        bid_record.current_bid_amount = bid_amount;

        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let coin = coin::withdraw<CoinType>(sender, (bid_amount as u64));
        coin::merge(reserve, coin);
    }

    public entry fun place_bid<CoinType>(sender: &signer, collection_name: String, token_id: u64, bid_amount: u256) acquires AuctionRecord, MarketReserve {
        let sender_addr = signer::address_of(sender);
        let nft_to_auction_map = &mut borrow_global_mut<AuctionRecord>(@lending_addr).nft_to_auction_map;
        let nft_to_auction = NFTToAuction {
            collection_name,
            token_id,
        };
        let bid_record = simple_map::borrow_mut<NFTToAuction, BidRecord>(nft_to_auction_map, &nft_to_auction);
        let require_bid_amount = bid_record.current_bid_amount + bid_record.current_debt * 101 / 100; // + 1% debt      
        assert!(bid_amount >= require_bid_amount, ERR_INSUFFICIENT_BALANCE);

        // refund
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let coin = coin::extract(reserve, (bid_record.current_bid_amount as u64));
        coin::deposit(bid_record.current_bid_addr, coin);

        bid_record.current_bid_addr = sender_addr;
        bid_record.current_bid_amount = bid_amount;

        // get new bid
        let coin = coin::withdraw<CoinType>(sender, (bid_amount as u64));
        coin::merge(reserve, coin);
    }

    public entry fun declare_winner<CoinType>(sender: &signer, collection_name: String, token_id: u64) acquires AuctionRecord, MarketReserve {
        let sender_addr = signer::address_of(sender);
        let nft_to_auction_map = &mut borrow_global_mut<AuctionRecord>(@lending_addr).nft_to_auction_map;
        let nft_to_auction = NFTToAuction {
            collection_name,
            token_id,
        };
        let bid_record = simple_map::borrow_mut<NFTToAuction, BidRecord>(nft_to_auction_map, &nft_to_auction);
        bid_record.winner_addr = bid_record.current_bid_addr;
        bid_record.winner_amount = bid_record.current_bid_amount;

        // repay debt and get nft collateral, then transfer to winer
        let creator_constructor_ref = &object::create_object(@lending_addr);
        let creator_extend_ref = object::generate_extend_ref(creator_constructor_ref);
        let creator = &object::generate_signer_for_extending(&creator_extend_ref);
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let coin = coin::extract(reserve, (bid_record.current_debt as u64));
        coin::deposit(signer::address_of(creator), coin);
        lending_pool::repay<CoinType>(creator, bid_record.current_debt);
        digital_asset::transfer_token(bid_record.winner_addr, collection_name, token_id);

        // deposit remaining amount to owner of address
        let remaining_amount = bid_record.current_bid_amount - bid_record.current_debt;
        let coin = coin::extract(reserve, (remaining_amount as u64));
        coin::deposit(sender_addr, coin);
    }   
    
    //====================================================================================
    //================================== View Fucntion ===================================
    //====================================================================================

    #[view]
    public fun get_numbers_nft_to_auction(): u64 acquires AuctionRecord {
        let nft_to_auction_list = &borrow_global<AuctionRecord>(@lending_addr).nft_to_auction_list;
        let number_nfts = vector::length(nft_to_auction_list);
        number_nfts
    } 

    #[view]
    public fun get_nft_to_auction(index: u64): (String, u64) acquires AuctionRecord {
        let nft_to_auction_list = &borrow_global<AuctionRecord>(@lending_addr).nft_to_auction_list;
        let nft = vector::borrow(nft_to_auction_list, index);
        (nft.collection_name, nft.token_id)
    } 

    #[view]
    public fun get_bid_information(collection_name: String, token_id: u64): (u256, address, u256, address, u256, address, u256) acquires AuctionRecord {
        let nft_to_auction_map = &borrow_global<AuctionRecord>(@lending_addr).nft_to_auction_map;
        let nft_to_auction = NFTToAuction {
            collection_name,
            token_id,
        };
        let bid_record = simple_map::borrow<NFTToAuction, BidRecord>(nft_to_auction_map, &nft_to_auction);
        (
            bid_record.current_debt,
            bid_record.first_bid_addr,
            bid_record.first_bid_amount,
            bid_record.current_bid_addr,
            bid_record.current_bid_amount,
            bid_record.winner_addr,
            bid_record.winner_amount,
        )
    }
}