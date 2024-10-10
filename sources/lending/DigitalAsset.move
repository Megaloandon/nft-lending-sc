module lending_addr::digital_asset {
    use std::signer;
    use std::debug::print;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_token_objects::aptos_token::{Self, AptosToken};
    use std::string::{Self, String};
    use aptos_std::string_utils;
    use std::simple_map::{Self, SimpleMap};

    const APTOS_MONKEY_COLLECTION_NAME: vector<u8> = b"Aptos Monkeys";
    const MEGALOANDON_COLLECTION_NAME: vector<u8> = b"Megaloandon";
    const COLLECTION_URI: vector<u8> = b"https://ipfs.bluemove.net/uploads/aptos-monkeys.png";
    const APTOS_MONKEY_COLLECTION_DESCRIPTION: vector<u8> = b"A group of skilled monkeys working together to build a civilized jungle. Each monkey has its unique intelligence to create long-lasting products to foster productivity and effectiveness in the Aptos ecosystem.";
    const MEGALOANDON_COLLECTION_DESCRIPTION: vector<u8> = b"Megaloandon collections represent for debt of borrower";

    const ERR_TEST: u64 = 1000;

    friend lending_addr::lending_pool;
    friend lending_addr::lending_pool_test;
    friend lending_addr::exchange;

    struct NFTCollectionCreator has key {
        extend_ref: ExtendRef
    }

    struct NFT has key, store {
        name: String,
        description: String,
        uri: String,
        addr: address,
    }

    struct Collection has key, store {
        max_supply: u64,
        collection_description: String,
        collection_uri: String,
        nft_record: SimpleMap<u64, NFT>,
        debt_nft_address: SimpleMap<u64, address>,
    }

    struct CollectionManager has key {
        collection_record: SimpleMap<String, Collection>,
    }

    public fun initialize(sender: &signer) {
        let creator_constructor_ref = &object::create_object(@lending_addr);
        let creator_extend_ref = object::generate_extend_ref(creator_constructor_ref);
        let creator_signer = &object::generate_signer_for_extending(&creator_extend_ref);
        move_to(sender, NFTCollectionCreator { 
            extend_ref: creator_extend_ref
        });
        let max_supply = 100000;

        move_to(sender, CollectionManager {
            collection_record: simple_map::create(),
        });

        aptos_token::create_collection(
            creator_signer,
            string::utf8(MEGALOANDON_COLLECTION_DESCRIPTION),
            max_supply,
            string::utf8(MEGALOANDON_COLLECTION_NAME),
            string::utf8(COLLECTION_URI),
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            0, 100,
        );
    }

    public entry fun create_collection (
        collection_description: String,
        max_supply: u64,
        collection_name: String,
        collection_uri: String,
    ) acquires NFTCollectionCreator, CollectionManager {
        let extend_ref = &borrow_global<NFTCollectionCreator>(@lending_addr).extend_ref;
        let creator = &object::generate_signer_for_extending(extend_ref);
        let collection_record = &mut borrow_global_mut<CollectionManager>(@lending_addr).collection_record;
        let collection = Collection {
            max_supply,
            collection_description,
            collection_uri,
            nft_record: simple_map::create(),
            debt_nft_address: simple_map::create(),
        };
        simple_map::add(collection_record, collection_name, collection);
        aptos_token::create_collection(
            creator,
            collection_description,
            max_supply,
            collection_name,
            collection_uri,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            0, 100,
        );
    }

    public entry fun mint_token(
        owner: address, 
        collection_name: String,
        token_id: u64,
        name: String,
        description: String, 
        uri: String,
    ) acquires NFTCollectionCreator, CollectionManager {
        let creator_extend_ref = &borrow_global<NFTCollectionCreator>(@lending_addr).extend_ref;
        let collection_record = &mut borrow_global_mut<CollectionManager>(@lending_addr).collection_record;
        let collection = simple_map::borrow_mut<String, Collection>(collection_record, &collection_name);
        let creator = &object::generate_signer_for_extending(creator_extend_ref);
        let temp = string::utf8(b" #");
        string::append(&mut name, temp);
        string::append(
            &mut name,
            string_utils::to_string(&token_id)
        );

        let original_token = aptos_token::mint_token_object(
            creator,
            collection_name,
            description,
            name,
            uri,
            vector[],
            vector[],
            vector[],
        );

        let debt_token = aptos_token::mint_token_object(
            creator,
            string::utf8(MEGALOANDON_COLLECTION_NAME),
            description,
            name,
            uri,
            vector[],
            vector[],
            vector[],
        );
        object::transfer(creator, original_token, owner);
        object::transfer(creator, debt_token, signer::address_of(creator));
        let debt_token_addr = object::object_address(&debt_token);
        simple_map::add(&mut collection.debt_nft_address, token_id, debt_token_addr);

        let original_token_addr = object::object_address(&original_token);
        let nft = NFT {
            name: name,
            description: description,
            uri: uri,
            addr: original_token_addr,
        };
        simple_map::add(&mut collection.nft_record, token_id, nft);    
    }

    public entry fun withdraw_token(owner: &signer, collection_name: String, token_id: u64) acquires NFTCollectionCreator, CollectionManager {
        let token = get_token(collection_name, token_id);
        let creator_extend_ref = &borrow_global<NFTCollectionCreator>(@lending_addr).extend_ref;
        let creator = &object::generate_signer_for_extending(creator_extend_ref);
        let receiver = signer::address_of(creator);
        object::transfer(owner, token, receiver);
    }

    public entry fun transfer_debt_token(owner_addr: address, collection_name: String, token_id: u64) acquires NFTCollectionCreator, CollectionManager {
        let creator_extend_ref = &borrow_global<NFTCollectionCreator>(@lending_addr).extend_ref;
        let creator = &object::generate_signer_for_extending(creator_extend_ref);
        let debt_token = get_debt_token(collection_name, token_id);
        object::transfer(creator, debt_token, owner_addr);
    }

    public entry fun withdraw_debt_token(owner: &signer, collection_name: String, token_id: u64) acquires NFTCollectionCreator, CollectionManager {
        let creator_extend_ref = &borrow_global<NFTCollectionCreator>(@lending_addr).extend_ref;
        let creator = &object::generate_signer_for_extending(creator_extend_ref);
        let debt_token = get_debt_token(collection_name, token_id);
        object::transfer(owner, debt_token, signer::address_of(creator));
    }

    public entry fun transfer_token(owner_addr: address, collection_name: String, token_id: u64) acquires NFTCollectionCreator, CollectionManager {
        let token = get_token(collection_name, token_id);
        let creator_extend_ref = &borrow_global<NFTCollectionCreator>(@lending_addr).extend_ref;
        let creator = &object::generate_signer_for_extending(creator_extend_ref);
        object::transfer(creator, token, owner_addr);
    }

    public entry fun delete_token(collection_name: String, token_id: u64) acquires NFTCollectionCreator, CollectionManager {
        let creator_extend_ref = &borrow_global<NFTCollectionCreator>(@lending_addr).extend_ref;
        let creator = &object::generate_signer_for_extending(creator_extend_ref);
        let token = get_token(collection_name, token_id);
        aptos_token::burn(creator, token);
    }

    public fun get_token(collection_name: String, token_id: u64): Object<AptosToken> acquires CollectionManager {
        let token_addr = get_address_token(collection_name, token_id);
        let token = object::address_to_object(token_addr);
        token
    }

    public fun get_debt_token(collection_name: String, token_id: u64): Object<AptosToken> acquires CollectionManager {
        let token_addr = get_address_debt_token(collection_name, token_id);
        let token = object::address_to_object(token_addr);
        token
    }

    #[view]
    public fun get_address_token(collection_name: String, token_id: u64): address acquires CollectionManager {
        let collection_record = &borrow_global<CollectionManager>(@lending_addr).collection_record;
        let collection = simple_map::borrow<String, Collection>(collection_record, &collection_name);
        let token_addr = simple_map::borrow<u64, NFT>(&collection.nft_record, &token_id).addr;
        token_addr
    }

    #[view]
    public fun get_address_debt_token(collection_name: String, token_id: u64): address acquires CollectionManager {
        let collection_record = &borrow_global<CollectionManager>(@lending_addr).collection_record;
        let collection = simple_map::borrow<String, Collection>(collection_record, &collection_name);
        let token_addr = *simple_map::borrow<u64, address>(&collection.debt_nft_address, &token_id);
        token_addr
    }

    #[view]
    public fun get_owner_token(collection_name: String, token_id: u64): address acquires CollectionManager {
        let token = get_token(collection_name, token_id);
        let owner_addr = object::owner(token);
        owner_addr
    }

    #[view]
    public fun get_owner_debt_token(collection_name: String, token_id: u64): address acquires CollectionManager {
        let token = get_debt_token(collection_name, token_id);
        let owner_addr = object::owner(token);
        owner_addr
    }

    #[view]
    public fun get_token_data(collection_name: String, token_id: u64): (String, String, String) acquires CollectionManager {
        let collection_record = &borrow_global<CollectionManager>(@lending_addr).collection_record;
        let collection = simple_map::borrow<String, Collection>(collection_record, &collection_name);
        let nft = simple_map::borrow<u64, NFT>(&collection.nft_record, &token_id);
        (nft.name, nft.description, nft.uri)
    }

    #[test(sender = @lending_addr, user1 = @0x123, user2 = @0x1234)]
    fun test_create_transfer_token(sender: &signer, user1: &signer, user2: &signer) acquires NFTCollectionCreator, CollectionManager {
        let sender_addr = signer::address_of(sender);
        let user1_addr = signer::address_of(user1);
        initialize(sender);
        let collection_name = string::utf8(APTOS_MONKEY_COLLECTION_NAME);
        let collection_description = string::utf8(APTOS_MONKEY_COLLECTION_DESCRIPTION);
        let collection_uri = string::utf8(COLLECTION_URI);
        let max_supply = 7777;
        create_collection(
            collection_description,
            max_supply,
            collection_name,
            collection_uri
        );
        mint_token(
            signer::address_of(sender), 
            collection_name,
            329,
            string::utf8(b"Name"),
            string::utf8(b"Description"),
            string::utf8(b"Uri"),
        );
        let token_addr = get_address_token(collection_name, 329);
        // print(&token_addr);

        mint_token(
            signer::address_of(sender), 
            collection_name,
            1214,
            string::utf8(b"Name"),
            string::utf8(b"Description"),
            string::utf8(b"Uri"),
        );
        let token_addr_1 = get_address_token(collection_name, 1214);
        // print(&token_addr_1);
        

        withdraw_token(sender, collection_name, 329);
        transfer_token(sender_addr, collection_name, 329);
        // let owner_addr = get_owner_token(329);
        // assert!(owner_addr == user1_addr, ERR_TEST);
        delete_token(collection_name, 329);

        let (name, description, uri) = get_token_data(collection_name, 329);
        // print(&name);
        // print(&description);
        // print(&uri);
    }
}