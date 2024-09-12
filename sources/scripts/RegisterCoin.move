script {
    fun register<CoinType>(user: &signer) {
        aptos_framework::managed_coin::register<CoinType>(user)
    }
}