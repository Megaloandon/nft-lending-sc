module lending_addr::storage {
    use std::vector;
    use std::string::{Self, String};
    use std::simple_map::{Self, SimpleMap};

    friend lending_addr::exchange;

    struct NFT has key, store, drop, copy {
        collection_name: String,
        token_id: u64,
    }

    struct ListedNFT has key {
        nft_owner: SimpleMap<NFT, address>,
        instantly_nft_list: vector<NFT>,
        offer_nft_list: vector<NFT>,
        offer_nft_map: SimpleMap<NFT, OfferRecord>,
    }

    struct Offer has key, store, drop {
        offer_price: u256,
        offer_time: u256,
    }

    struct OfferRecord has key, store, drop {
        user_offer_list: vector<address>, // list user address who make offer
        user_offer_map: SimpleMap<address, Offer>, // map user address and their offer
    }

    fun init_module(sender: &signer) {
        move_to(sender, ListedNFT {
            nft_owner: simple_map::create(),
            instantly_nft_list: vector::empty(),
            offer_nft_list: vector::empty(),
            offer_nft_map: simple_map::create(),
        });
    }

    //============================== Setter Function ==================================

    public fun add_instantly_nft(collection_name: String, token_id: u64, owner_addr: address) acquires ListedNFT {
        let instantly_nft = borrow_global_mut<ListedNFT>(@lending_addr);
        let nft_owner = &mut instantly_nft.nft_owner;
        let instantly_nft_list = &mut instantly_nft.instantly_nft_list; 
        let nft = NFT {
            collection_name,
            token_id,
        };
        simple_map::add(nft_owner, nft, owner_addr);
        let nft = NFT {
            collection_name,
            token_id
        };
        vector::push_back(instantly_nft_list, nft);
    }
 
    public fun add_offer_nft(collection_name: String, token_id: u64, owner_addr: address) acquires ListedNFT {
        let offer_nft = borrow_global_mut<ListedNFT>(@lending_addr);
        let nft_owner = &mut offer_nft.nft_owner;
        let offer_nft_list = &mut offer_nft.offer_nft_list;
        let offer_nft_map = &mut offer_nft.offer_nft_map;
        let offer_record = OfferRecord {
            user_offer_list: vector::empty(),
            user_offer_map: simple_map::create(),
        };
        let nft = NFT {
            collection_name,
            token_id,
        };
        simple_map::add(nft_owner, copy nft, owner_addr);
        vector::push_back(offer_nft_list, copy nft);
        simple_map::add(offer_nft_map, copy nft, offer_record);
    }

    public fun remove_instantly_nft(collection_name: String, token_id: u64) acquires ListedNFT {
        let instantly_nft = borrow_global_mut<ListedNFT>(@lending_addr);
        let nft_owner = &mut instantly_nft.nft_owner;
        let instantly_nft_list = &mut instantly_nft.instantly_nft_list;
        let nft = NFT {
            collection_name,
            token_id,
        };
        simple_map::remove(nft_owner, &nft);
        vector::remove_value(instantly_nft_list, &nft);
    }
    
    public fun remove_offer_nft(collection_name: String, token_id: u64) acquires ListedNFT {
        let offer_nft = borrow_global_mut<ListedNFT>(@lending_addr);
        let nft_owner = &mut offer_nft.nft_owner;
        let offer_nft_list = &mut offer_nft.offer_nft_list;
        let offer_nft_map = &mut offer_nft.offer_nft_map;
        let nft = NFT {
            collection_name,
            token_id,
        };
        simple_map::remove(nft_owner, &nft);
        vector::remove_value(offer_nft_list, &nft);
        simple_map::remove(offer_nft_map, &nft);
    }

    public fun user_add_offer(user_addr: address, collection_name: String, token_id: u64, offer_price: u256, offer_time: u256) acquires ListedNFT {
        let offer_nft_map = &mut borrow_global_mut<ListedNFT>(@lending_addr).offer_nft_map;
        let nft = NFT {
            collection_name,
            token_id,
        };
        let offer_record = simple_map::borrow_mut<NFT, OfferRecord>(offer_nft_map, &nft);
        let user_offer_list = &mut offer_record.user_offer_list;
        let user_offer_map = &mut offer_record.user_offer_map;
        vector::push_back(user_offer_list, user_addr);
        let offer = Offer {
            offer_price: offer_price,
            offer_time: offer_time,
        };
        simple_map::add(user_offer_map, user_addr, offer);
    }

    public fun user_remove_offer(offer_owner: address, collection_name: String, token_id: u64) acquires ListedNFT {
        let offer_nft_map = &mut borrow_global_mut<ListedNFT>(@lending_addr).offer_nft_map;
        let nft = NFT {
            collection_name,
            token_id,
        };
        let offer_record = simple_map::borrow_mut<NFT, OfferRecord>(offer_nft_map, &nft);
        let user_offer_list = &mut offer_record.user_offer_list;
        let user_offer_map = &mut offer_record.user_offer_map;
        vector::remove_value(user_offer_list, &offer_owner);
        simple_map::remove(user_offer_map, &offer_owner);
    }
    
    //============================== Getter Function ==================================

    public fun get_numbers_instantly_nft(): u64 acquires ListedNFT {
        let instantly_nft_list = &borrow_global<ListedNFT>(@lending_addr).instantly_nft_list;
        let numbers = vector::length(instantly_nft_list);
        numbers
    }

    public fun get_instantly_nft(index: u64): (String, u64) acquires ListedNFT {
        let instantly_nft_list = &borrow_global<ListedNFT>(@lending_addr).instantly_nft_list;
        let instantly_nft = vector::borrow(instantly_nft_list, index);
        (instantly_nft.collection_name, instantly_nft.token_id)
    }

    public fun get_numbers_offer_nft(): u64 acquires ListedNFT {
        let offer_nft_list = &borrow_global<ListedNFT>(@lending_addr).offer_nft_list;
        let numbers = vector::length(offer_nft_list);
        numbers
    }

    public fun get_offer_nft(index: u64): (String, u64) acquires ListedNFT {
        let offer_nft_list = &borrow_global<ListedNFT>(@lending_addr).offer_nft_list;
        let offer_nft = vector::borrow(offer_nft_list, index);
        (offer_nft.collection_name, offer_nft.token_id)
    }

    public fun get_nft_owner_addr(collection_name: String, token_id: u64): address acquires ListedNFT {
        let nft_owner = &borrow_global<ListedNFT>(@lending_addr).nft_owner;
        let nft = NFT {
            collection_name,
            token_id,
        };
        let owner_addr = *simple_map::borrow<NFT, address>(nft_owner, &nft);
        owner_addr
    }

    public fun get_number_offers(collection_name: String, token_id: u64): u64 acquires ListedNFT {
        let offer_nft_map = &borrow_global<ListedNFT>(@lending_addr).offer_nft_map;
        let nft = NFT {
            collection_name,
            token_id
        };
        if(simple_map::contains_key<NFT, OfferRecord>(offer_nft_map, &nft) == false) {
            return 0;
        };
        let offer_record = simple_map::borrow<NFT, OfferRecord>(offer_nft_map, &nft);
        let user_offer_list = &offer_record.user_offer_list;
        let number_offers = vector::length(user_offer_list);
        number_offers
    }

    public fun get_offer(collection_name: String, token_id: u64, offer_id: u64): (address, u256, u256) acquires ListedNFT {
        let offer_nft_map = &borrow_global<ListedNFT>(@lending_addr).offer_nft_map;
        let nft = NFT {
            collection_name,
            token_id,
        };
        let offer_record = simple_map::borrow<NFT, OfferRecord>(offer_nft_map, &nft);
        let user_offer_list = &offer_record.user_offer_list;
        let user_offer_map = &offer_record.user_offer_map;
        let user_offer_address = vector::borrow(user_offer_list, offer_id);
        let offer = simple_map::borrow<address, Offer>(user_offer_map, user_offer_address);
        (*user_offer_address, offer.offer_price, offer.offer_time)
    }

    public fun get_offer_information(collection_name: String, token_id: u64, offer_owner: address): (u256, u256) acquires ListedNFT {
        let offer_nft_map = &borrow_global<ListedNFT>(@lending_addr).offer_nft_map;
        let nft = NFT {
            collection_name,
            token_id,
        };
        let offer_record = simple_map::borrow<NFT, OfferRecord>(offer_nft_map, &nft);
        let user_offer_map = &offer_record.user_offer_map;
        let offer = simple_map::borrow<address, Offer>(user_offer_map, &offer_owner);
        (offer.offer_price, offer.offer_time)
    }

    #[test_only]
    public fun init_module_for_tests(sender: &signer) {
        init_module(sender);
    }
}