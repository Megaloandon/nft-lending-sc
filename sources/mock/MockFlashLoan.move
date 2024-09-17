module lending_addr::mock_flash_loan {
    use std::signer;
    use aptos_framework::coin::{Self, Coin};
    use lending_addr::mega_coin::{Self, MockAPT};
    use lending_addr::exchange;

    struct MarketReserve<phantom CoinType> has key {
        reserve: Coin<CoinType>
    }

    struct Receipt has key {
        amount: u256,
    }

    fun init_module(sender: &signer) {
        move_to<MarketReserve<MockAPT>>(sender, MarketReserve<MockAPT> {
            reserve: coin::zero<MockAPT>(),
        });
        
        move_to(sender, Receipt {
            amount: 0,
        });
    }

    public fun deposit<CoinType>(sender: &signer, amount: u256) acquires MarketReserve {
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let coin = coin::withdraw<CoinType>(sender, (amount as u64));
        coin::merge(reserve, coin);
    }

    public fun flash_loan<CoinType>(sender: &signer, amount: u256) acquires MarketReserve, Receipt {
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let receipt = borrow_global_mut<Receipt>(@lending_addr);
        receipt.amount = amount;
        let coin = coin::extract(reserve, (amount as u64));
        coin::deposit(signer::address_of(sender), coin);
    }

    public fun repay_flash_loan<CoinType>(sender: &signer) acquires MarketReserve, Receipt {
        let reserve = &mut borrow_global_mut<MarketReserve<CoinType>>(@lending_addr).reserve;
        let receipt = borrow_global_mut<Receipt>(@lending_addr);
        let coin = coin::withdraw<CoinType>(sender, (receipt.amount as u64));
        coin::merge(reserve, coin);
        receipt.amount = 0;
    }

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