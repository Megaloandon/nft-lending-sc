module lending_addr::nft_minter {
    use std::signer;
    use std::debug::print;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_token_objects::aptos_token::{Self, AptosToken};
    use std::string::{Self, String};
    use std::simple_map::{Self, SimpleMap};

    const COLLECTION_NAME: vector<u8> = b"Aptos Monkeys";
    const COLLECTION_URI: vector<u8> = b"https://ipfs.bluemove.net/uploads/aptos-monkeys.png";

    struct NFTCollectionCreator has key {
        extend_ref: ExtendRef
    }

    struct AddressManager has key {
        address_record: SimpleMap<String, address>
    }

    fun init_module(sender: &signer) {
        let creator_constructor_ref = &object::create_object(@lending_addr);
        let extend_ref = object::generate_extend_ref(creator_constructor_ref);
        move_to(sender, NFTCollectionCreator { 
            extend_ref 
        });
        let creator_signer = &object::generate_signer(creator_constructor_ref);
        let max_supply = 1000;

        move_to(sender, AddressManager {
            address_record: simple_map::create(),
        });
        
        aptos_token::create_collection(
            creator_signer,
            string::utf8(b"NFT Description"),
            max_supply,
            string::utf8(COLLECTION_NAME),
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

    public entry fun mint_token(
        owner: address, 
        description: String, 
        name: String, 
        uri: String
    ) acquires NFTCollectionCreator, AddressManager{
        let creator_extend_ref = &borrow_global<NFTCollectionCreator>(@lending_addr).extend_ref;
        let address_manager = borrow_global_mut<AddressManager>(@lending_addr);
        let creator = &object::generate_signer_for_extending(creator_extend_ref);
        let token = aptos_token::mint_token_object(
            creator,
            string::utf8(COLLECTION_NAME),
            description,
            name,
            uri,
            vector[],
            vector[],
            vector[],
        );
        object::transfer(creator, token, owner);
        let token_addr = object::object_address(&token);
        simple_map::add(&mut address_manager.address_record, name, token_addr);
    }

    public entry fun transfer_token(owner: &signer, token_addr: address, receiver: address) {
        let token = get_token(token_addr);
        object::transfer(owner, token, receiver);
    }

    public entry fun delete_token(token_addr: address) acquires NFTCollectionCreator {
        let creator_extend_ref = &borrow_global<NFTCollectionCreator>(@lending_addr).extend_ref;
        let creator = &object::generate_signer_for_extending(creator_extend_ref);
        let token = get_token(token_addr);
        aptos_token::burn(creator, token);
    }

    public fun get_token(object: address): Object<AptosToken> {
        let token = object::address_to_object(object);
        token
    }

    #[view]
    public fun get_address_token(name: String): address acquires AddressManager {
        let address_manager = borrow_global<AddressManager>(@lending_addr);
        let token_addr = *simple_map::borrow<String, address>(&address_manager.address_record, &name);
        token_addr
    }

    #[view]
    public fun get_owner_token(object: address): address {
        let token = get_token(object);
        let owner_addr = object::owner(token);
        owner_addr
    }

    #[test(sender = @lending_addr, user1 = @0x123, user2 = @0x1234)]
    fun test_create_transfer_token(sender: &signer, user1: &signer, user2: &signer) acquires NFTCollectionCreator, AddressManager {
        init_module(sender);
        mint_token(
            signer::address_of(sender), 
            string::utf8(b"Description"),
            string::utf8(b"Name"),
            string::utf8(b"Uri"),
        );
        let token_addr = get_address_token(string::utf8(b"Name"));
        print(&token_addr);

        mint_token(
            signer::address_of(sender), 
            string::utf8(b"Description"),
            string::utf8(b"Name1"),
            string::utf8(b"Uri"),
        );
        let token_addr_1 = get_address_token(string::utf8(b"Name1"));
        print(&token_addr_1);

        let token = get_token(token_addr);
        transfer_token(sender, token_addr, signer::address_of(user1));
        transfer_token(user1, token_addr, signer::address_of(user2));
        let owner_addr = get_owner_token(token_addr);
        print(&owner_addr);
        delete_token(token_addr);
    }
}