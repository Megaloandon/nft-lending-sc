module lending_addr::storage {
    use std::vector;

    friend lending_addr::exchange;

    struct ListedNFT has key {
        instantly_nft: vector<u64>,
        offer_nft: vector<u64>,
    }

    fun init_module(sender: &signer) {
        move_to(sender, ListedNFT {
            instantly_nft: vector::empty(),
            offer_nft: vector::empty()
        });
    }

    //============================== Setter Function ==================================

    public fun add_instantly_nft(token_id: u64) acquires ListedNFT {
        let instantly_nft = &mut borrow_global_mut<ListedNFT>(@lending_addr).instantly_nft;
        vector::push_back(instantly_nft, token_id);
    }

    public fun add_offer_nft(token_id: u64) acquires ListedNFT {
        let offer_nft = &mut borrow_global_mut<ListedNFT>(@lending_addr).offer_nft;
        vector::push_back(offer_nft, token_id);
    }

    //============================== Getter Function ==================================

    public fun get_all_instantly_nft(): vector<u64> acquires ListedNFT {
        let instantly_nft = borrow_global<ListedNFT>(@lending_addr).instantly_nft;
        instantly_nft
    }

    public fun get_all_offer_nft(): vector<u64> acquires ListedNFT {
        let offer_nft = borrow_global<ListedNFT>(@lending_addr).offer_nft;
        offer_nft
    }
}