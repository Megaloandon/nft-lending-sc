module lending_addr::lending_pool_test {
    use std::debug::print;
    use aptos_framework::timestamp;

    #[test_only]
    public fun set_up_test(aptos_framework: signer) {
        // set up global time for testing purpose
        timestamp::set_time_has_started_for_testing(&aptos_framework);
    }

    #[test (aptos_framework = @aptos_framework)]
    public entry fun test_timestamp(
        aptos_framework: signer
    ) {
        set_up_test(aptos_framework);
        let now = timestamp::now_seconds();
        timestamp::update_global_time_for_test_secs(now + 10);
        let now = timestamp::now_seconds();
        print(&now);
    }
}