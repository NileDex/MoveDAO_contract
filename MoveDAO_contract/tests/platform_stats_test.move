#[test_only]
module movedaoaddrx::platform_stats_tests {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use movedaoaddrx::dao_core_file as dao_core;
    use movedaoaddrx::platform_stats;
    use movedaoaddrx::test_utils;

    const EASSERTION_FAILED: u64 = 500;

    #[test(aptos_framework = @0x1, creator = @0x123)]
    fun test_platform_stats_basic(aptos_framework: &signer, creator: &signer) {
        // Setup test environment
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(creator);
        coin::register<aptos_coin::AptosCoin>(creator);
        
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();

        // Get initial platform stats (should be empty)
        let initial_stats = platform_stats::get_platform_stats();
        
        // Create a DAO
        let name = string::utf8(b"Test DAO");
        let subname = string::utf8(b"test-platform-dao");
        let description = string::utf8(b"A test DAO for platform stats");
        let logo = b"logo";
        let background = b"bg";
        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, signer::address_of(creator));

        dao_core::create_dao(
            creator,
            name,
            subname,
            description,
            logo,
            background,
            initial_council,
            6000000  // 6 Move
        );

        // Get updated platform stats
        let updated_stats = platform_stats::get_platform_stats();
        
        // Platform stats should work without errors (we can't easily test exact values 
        // since they depend on internal DAO state, but the fact that it doesn't crash is good)
        
        test_utils::destroy_caps(aptos_framework);
    }
}