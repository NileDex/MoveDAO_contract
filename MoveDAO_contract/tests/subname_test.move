#[test_only]
module movedaoaddrx::subname_tests {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use movedaoaddrx::dao_core_file as dao_core;
    use movedaoaddrx::test_utils;

    const EASSERTION_FAILED: u64 = 300;
    const ESUBNAME_ALREADY_EXISTS: u64 = 611;

    #[test(aptos_framework = @0x1, creator1 = @0x123, creator2 = @0x456)]
    fun test_subname_uniqueness_enforcement(aptos_framework: &signer, creator1: &signer, creator2: &signer) {
        // Setup test environment
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(creator1);
        test_utils::setup_test_account(creator2);
        coin::register<aptos_coin::AptosCoin>(creator1);
        coin::register<aptos_coin::AptosCoin>(creator2);
        
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();

        // Test data for first DAO
        let name1 = string::utf8(b"Gaming DAO");
        let subname = string::utf8(b"elite-gaming"); // This subname should be unique
        let description1 = string::utf8(b"A gaming community DAO");
        let logo = b"logo";
        let background = b"bg";
        let initial_council1 = vector::empty<address>();
        vector::push_back(&mut initial_council1, signer::address_of(creator1));

        // Create first DAO successfully
        dao_core::create_dao(
            creator1,
            name1,
            subname,
            description1,
            logo,
            background,
            initial_council1,
            6000000  // 6 Move
        );

        // Verify first DAO was created and subname is taken
        let creator1_addr = signer::address_of(creator1);
        assert!(dao_core::dao_exists(creator1_addr), EASSERTION_FAILED);
        assert!(dao_core::is_subname_taken(subname), EASSERTION_FAILED + 1);
        assert!(dao_core::get_subname_owner(subname) == creator1_addr, EASSERTION_FAILED + 2);

        // Test data for second DAO with same subname
        let name2 = string::utf8(b"Sports DAO");
        let description2 = string::utf8(b"A sports community DAO");
        let initial_council2 = vector::empty<address>();
        vector::push_back(&mut initial_council2, signer::address_of(creator2));

        // Attempt to create second DAO with same subname - should fail
        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, creator1 = @0x123, creator2 = @0x456)]
    #[expected_failure(abort_code = 611, location = movedaoaddrx::dao_core_file)]
    fun test_duplicate_subname_fails(aptos_framework: &signer, creator1: &signer, creator2: &signer) {
        // Setup test environment
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(creator1);
        test_utils::setup_test_account(creator2);
        coin::register<aptos_coin::AptosCoin>(creator1);
        coin::register<aptos_coin::AptosCoin>(creator2);
        
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();

        // Create first DAO
        let name1 = string::utf8(b"Gaming DAO");
        let subname = string::utf8(b"elite-gaming");
        let description1 = string::utf8(b"A gaming community DAO");
        let logo = b"logo";
        let background = b"bg";
        let initial_council1 = vector::empty<address>();
        vector::push_back(&mut initial_council1, signer::address_of(creator1));

        dao_core::create_dao(creator1, name1, subname, description1, logo, background, initial_council1, 6000000);

        // Try to create second DAO with same subname - should fail with ESUBNAME_ALREADY_EXISTS
        let name2 = string::utf8(b"Sports DAO");
        let description2 = string::utf8(b"A sports community DAO");
        let initial_council2 = vector::empty<address>();
        vector::push_back(&mut initial_council2, signer::address_of(creator2));

        dao_core::create_dao(creator2, name2, subname, description2, logo, background, initial_council2, 6000000);
    }

    #[test(aptos_framework = @0x1, creator1 = @0x123, creator2 = @0x456)]
    fun test_different_subnames_allowed(aptos_framework: &signer, creator1: &signer, creator2: &signer) {
        // Setup test environment
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(creator1);
        test_utils::setup_test_account(creator2);
        coin::register<aptos_coin::AptosCoin>(creator1);
        coin::register<aptos_coin::AptosCoin>(creator2);
        
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();

        // Create first DAO
        let name1 = string::utf8(b"Gaming DAO");
        let subname1 = string::utf8(b"elite-gaming");
        let description1 = string::utf8(b"A gaming community DAO");
        let logo = b"logo";
        let background = b"bg";
        let initial_council1 = vector::empty<address>();
        vector::push_back(&mut initial_council1, signer::address_of(creator1));

        dao_core::create_dao(creator1, name1, subname1, description1, logo, background, initial_council1, 6000000);

        // Create second DAO with different subname - should succeed
        let name2 = string::utf8(b"Gaming DAO"); // Same name is OK
        let subname2 = string::utf8(b"pro-gaming"); // Different subname
        let description2 = string::utf8(b"A professional gaming DAO");
        let initial_council2 = vector::empty<address>();
        vector::push_back(&mut initial_council2, signer::address_of(creator2));

        dao_core::create_dao(creator2, name2, subname2, description2, logo, background, initial_council2, 6000000);

        // Verify both DAOs exist
        let creator1_addr = signer::address_of(creator1);
        let creator2_addr = signer::address_of(creator2);
        assert!(dao_core::dao_exists(creator1_addr), EASSERTION_FAILED);
        assert!(dao_core::dao_exists(creator2_addr), EASSERTION_FAILED + 1);
        
        // Verify both subnames are taken by different owners
        assert!(dao_core::is_subname_taken(subname1), EASSERTION_FAILED + 2);
        assert!(dao_core::is_subname_taken(subname2), EASSERTION_FAILED + 3);
        assert!(dao_core::get_subname_owner(subname1) == creator1_addr, EASSERTION_FAILED + 4);
        assert!(dao_core::get_subname_owner(subname2) == creator2_addr, EASSERTION_FAILED + 5);
        
        // Verify total subnames count
        assert!(dao_core::get_total_subnames() == 2, EASSERTION_FAILED + 6);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1)]
    fun test_subname_registry_functions(aptos_framework: &signer) {
        // Setup test environment
        account::create_account_for_test(@0x1);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();

        // Test registry initialization
        assert!(dao_core::is_subname_registry_initialized(), EASSERTION_FAILED);
        assert!(dao_core::get_total_subnames() == 0, EASSERTION_FAILED + 1);

        // Test subname availability check for non-existent subname
        let test_subname = string::utf8(b"non-existent");
        assert!(!dao_core::is_subname_taken(test_subname), EASSERTION_FAILED + 2);

        test_utils::destroy_caps(aptos_framework);
    }
}