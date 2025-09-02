#[test_only]
module movedaoaddrx::create_dao_tests {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use movedaoaddrx::dao_core_file as dao_core;
    use movedaoaddrx::test_utils;

    const EASSERTION_FAILED: u64 = 200;

    #[test(aptos_framework = @0x1, creator = @0x123)]
    fun test_dao_creation(aptos_framework: &signer, creator: &signer) {
        // Setup test environment
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1); // Advance time to ensure now_seconds() > 0
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(creator);
        coin::register<aptos_coin::AptosCoin>(creator);
        
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();

        // Test data
        let name = string::utf8(b"My DAO");
        let description = string::utf8(b"A test DAO");
        let logo = b"logo";
        let background = b"bg";
        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, signer::address_of(creator));

        // Create the DAO
        dao_core::create_dao(
            creator, 
            name,
            string::utf8(b"Subname"), 
            description, 
            logo, 
            background,
            initial_council, 
            30  // min_stake_to_join
        );

        // Verify DAO was created by checking stored data
        let creator_addr = signer::address_of(creator);
        let (stored_name, stored_description, _logo_is_url, _logo_url, stored_logo, _bg_is_url, _bg_url, stored_background, created_at) = 
            dao_core::get_dao_info(creator_addr);

        // Assertions to verify DAO creation
        assert!(stored_name == name, EASSERTION_FAILED);
        assert!(stored_description == description, EASSERTION_FAILED + 1);
        assert!(stored_logo == logo, EASSERTION_FAILED + 2);
        assert!(stored_background == background, EASSERTION_FAILED + 3);
        assert!(created_at > 0, EASSERTION_FAILED + 4); // Verify timestamp was set

        test_utils::destroy_caps(aptos_framework);
    }
}