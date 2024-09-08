module lending_addr::fungible_asset_minter {
    use std::signer;
    use std::vector;
    use std::debug::print;
    use std::aptos_account;
    use std::account;
    use std::option;
    use std::string::{Self, String};
    use std::simple_map::{Self, SimpleMap};
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset};
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::primary_fungible_store;

    const ERR_TEST: u64 = 101;

    struct FungibleAssetCreator has key {
        fa_generator_extend_ref: ExtendRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
    }
    
    // automatically called when deploy module
    fun init_module(sender: &signer) {
        let constructor_ref = object::create_named_object(sender, b"FA Generator");
        let fa_generator_extend_ref = object::generate_extend_ref(&constructor_ref);
        let fa = FungibleAssetCreator {
            fa_generator_extend_ref: fa_generator_extend_ref,
        };
        move_to(sender, fa);
    }


    // =============================== Entry Function =====================================

    // Initialize metadata object and store the refs
    public entry fun create_fa(
        sender_addr: address,
        name: String,
        symbol: String,
        decimals: u8,
        icon_uri: String,
        project_uri: String,
    ) acquires FungibleAssetCreator {
        let fa = borrow_global_mut<FungibleAssetCreator>(@lending_addr);
        let fa_generator_signer = object::generate_signer_for_extending(&fa.fa_generator_extend_ref);
        let fa_key_seed = *string::bytes(&name);
        vector::append(&mut fa_key_seed, b"-");
        vector::append(&mut fa_key_seed, *string::bytes(&symbol));
        let fa_obj_constructor_ref = &object::create_named_object(&fa_generator_signer, fa_key_seed);
        let fa_obj_signer = object::generate_signer(fa_obj_constructor_ref);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            fa_obj_constructor_ref,
            option::none(),
            name, 
            symbol, 
            decimals, 
            icon_uri, 
            project_uri,           
        );
        let mint_ref = fungible_asset::generate_mint_ref(fa_obj_constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(fa_obj_constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(fa_obj_constructor_ref);
        move_to(
            &fa_obj_signer,
            ManagedFungibleAsset {
                mint_ref,
                transfer_ref,
                burn_ref,
            }
        );
    }

    public entry fun mint(sender: &signer, to: address, amount: u256, name: String, symbol: String) acquires FungibleAssetCreator, ManagedFungibleAsset {
        let sender_addr = signer::address_of(sender);
        let asset = get_metadata(name, symbol);
        let managed_fungble_asset = authorized_borrow_refs(sender, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = fungible_asset::mint(&managed_fungble_asset.mint_ref, (amount as u64));
        fungible_asset::deposit_with_ref(&managed_fungble_asset.transfer_ref, to_wallet, fa);
    }

    public entry fun transfer(sender: &signer, from: address, to: address, amount: u256, name: String, symbol: String) acquires FungibleAssetCreator, ManagedFungibleAsset {
        let sender_addr = signer::address_of(sender);
        let asset = get_metadata(name, symbol);
        let transfer_ref = &authorized_borrow_refs(sender, asset).transfer_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = withdraw(from_wallet, amount, transfer_ref);
        deposit(to_wallet, fa, transfer_ref);
    }

    public entry fun burn(sender: &signer, from: address, amount: u256, name: String, symbol: String) acquires FungibleAssetCreator, ManagedFungibleAsset {
        let sender_addr = signer::address_of(sender);
        let asset = get_metadata(name, symbol);
        let burn_ref = &authorized_borrow_refs(sender, asset).burn_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        fungible_asset::burn_from(burn_ref, from_wallet, (amount as u64));
    }

    // ========================================= View Function ==========================================

    #[view]
    public fun get_balance(sender_addr: address, name: String, symbol: String): u256 acquires FungibleAssetCreator {
        let object_address = get_fa_obj_address(name, symbol);
        let fa_metadata_obj: Object<Metadata> = object::address_to_object(object_address);
        (primary_fungible_store::balance(sender_addr, fa_metadata_obj) as u256)
    }
    

    #[view]
    public fun get_total_supply(name: String, symbol: String): u256 acquires FungibleAssetCreator {
        let asset = get_metadata(name, symbol);
        let total_supply = fungible_asset::supply(asset);
        if(option::is_some(&total_supply)) {
            let value = option::borrow(&total_supply);
            let result = (*value as u256);
            result
        } else {
            0
        }
    }

    #[view]
    public fun get_token_address(name: String, symbol: String): address acquires FungibleAssetCreator {
        get_fa_obj_address(name, symbol)
    }

    // ========================================= Helper Function ========================================
    
    public fun init_module_for_test(sender: &signer) {
        let constructor_ref = object::create_named_object(sender, b"FA Generator");
        let fa_generator_extend_ref = object::generate_extend_ref(&constructor_ref);
        let fa = FungibleAssetCreator {
            fa_generator_extend_ref: fa_generator_extend_ref,
        };
        move_to(sender, fa);
    }

    public fun get_metadata(name: String, symbol: String): Object<Metadata> acquires FungibleAssetCreator {
        let asset_address = get_fa_obj_address(name, symbol);
        object::address_to_object(asset_address)
    }
    
    public fun get_fa_obj_address(name: String, symbol: String): address acquires FungibleAssetCreator {
        let fa = borrow_global<FungibleAssetCreator>(@lending_addr);
        let fa_generator_address = object::address_from_extend_ref(&fa.fa_generator_extend_ref);
        let fa_key_seed = *string::bytes(&name);
        vector::append(&mut fa_key_seed, b"-");
        vector::append(&mut fa_key_seed, *string::bytes(&symbol));
        object::create_object_address(&fa_generator_address, fa_key_seed)
    }

    fun deposit<T: key>(store: Object<T>, fa: FungibleAsset, transfer_ref: &TransferRef) {
        fungible_asset::deposit_with_ref(transfer_ref, store, fa);
    }

    fun withdraw<T: key>(store: Object<T>, amount: u256, transfer_ref: &TransferRef): FungibleAsset {
        fungible_asset::withdraw_with_ref(transfer_ref, store, (amount as u64))
    }

    inline fun authorized_borrow_refs(owner: &signer, asset: Object<Metadata>): &ManagedFungibleAsset acquires ManagedFungibleAsset {
        // checkowner
        borrow_global<ManagedFungibleAsset>(object::object_address(&asset))
    }
    
    // ======================================= Unit Test =========================================

    #[test_only]
    public fun create_token_test(
        sender: &signer,
        name: String,
        symbol: String,
        decimals: u8,
        icon_uri: String,
        project_uri: String,
        initial_supply: u256,
    ): Object<Metadata> acquires FungibleAssetCreator, ManagedFungibleAsset {
        create_fa(signer::address_of(sender), name, symbol, decimals, icon_uri, project_uri);
        mint(sender, signer::address_of(sender), initial_supply, name, symbol);
        let asset = get_metadata(name, symbol);
        asset 
    }

    #[test(sender = @lending_addr, user1 = @0x123, user2 = @0x1234)]
    public fun test_flow(sender: signer, user1: signer, user2: signer) acquires FungibleAssetCreator, ManagedFungibleAsset {
        let sender_addr = signer::address_of(&sender);
        let user1_addr = signer::address_of(&user1);
        let user2_addr = signer::address_of(&user2);
        init_module(&sender);
        let usdt_name = string::utf8(b"USD Tether");
        let usdt_symbol = string::utf8(b"USDT");
        let eth_name = string::utf8(b"Ethereum");
        let eth_symbol = string::utf8(b"ETH");
        let usdt = create_token_test(
            &sender,
            usdt_name,
            usdt_symbol,
            6,
            string::utf8(b"http://example.com/favicon.ico"),
            string::utf8(b"http://example.com"),
            500,
        );

        let eth = create_token_test(
            &sender,
            eth_name,
            eth_symbol,
            6,
            string::utf8(b"http://example.com/favicon.ico"),
            string::utf8(b"http://example.com"),
            500,
        );

        transfer(&sender, sender_addr, user1_addr, 100, usdt_name, usdt_symbol);
        let sender_usd_balance = get_balance(sender_addr, usdt_name, usdt_symbol);
        assert!(sender_usd_balance == 400, ERR_TEST);
        let user1_usd_balance = get_balance(user1_addr, usdt_name, usdt_symbol);
        assert!(user1_usd_balance == 100, ERR_TEST);  

        transfer(&user1, user1_addr, user2_addr, 20, usdt_name, usdt_symbol);
        let user1_usd_balance = get_balance(user1_addr, usdt_name, usdt_symbol);
        assert!(user1_usd_balance == 80, ERR_TEST);  
        let user2_usd_balance = get_balance(user2_addr, usdt_name, usdt_symbol);
        assert!(user2_usd_balance == 20, ERR_TEST);  

        transfer(&sender, sender_addr, user1_addr, 200, eth_name, eth_symbol);
        let user1_eth_balance = get_balance(user1_addr, eth_name, eth_symbol);
        assert!(user1_eth_balance == 200, ERR_TEST);  
        let sender_eth_balance = get_balance(sender_addr, eth_name, eth_symbol);
        assert!(sender_eth_balance == 300, ERR_TEST);  

        let total_eth_supply = get_total_supply(eth_name, eth_symbol);
        assert!(total_eth_supply == 500, ERR_TEST);
        let total_usdt_supply = get_total_supply(usdt_name, usdt_symbol);
        assert!(total_usdt_supply == 500, ERR_TEST);

    }
}