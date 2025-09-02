#[test_only]
module movedaoaddrx::council_tests {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use movedaoaddrx::dao_core_file as dao_core;
    use movedaoaddrx::council;
    use movedaoaddrx::test_utils;

    const EASSERTION_FAILED: u64 = 200;

    #[test(aptos_framework = @0x1, alice = @0x123, _bob = @0x456, _charlie = @0x789)]
    public fun test_council_lifecycle(
        aptos_framework: &signer,
        alice: &signer,
        _bob: &signer,
        _charlie: &signer
    ) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x456);
        account::create_account_for_test(@0x789);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, signer::address_of(alice));
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_addr = @0x123;
        let council_obj = dao_core::get_council_object(dao_addr);
        
        // Add second member (alice is already initial member)
        council::add_council_member_to_object(alice, dao_addr, council_obj, @0x456);
        assert!(council::get_member_count_from_object(council_obj) == 2, EASSERTION_FAILED);
        assert!(council::is_council_member_in_object(council_obj, @0x456), EASSERTION_FAILED + 1);

        // Add third member
        council::add_council_member_to_object(alice, dao_addr, council_obj, @0x789);
        assert!(council::get_member_count_from_object(council_obj) == 3, EASSERTION_FAILED + 2);
        assert!(council::is_council_member_in_object(council_obj, @0x789), EASSERTION_FAILED + 3);

        // Remove member
        council::remove_council_member_from_object(alice, dao_addr, council_obj, @0x456);
        assert!(council::get_member_count_from_object(council_obj) == 2, EASSERTION_FAILED + 4);
        assert!(!council::is_council_member_in_object(council_obj, @0x456), EASSERTION_FAILED + 5);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123, _bob = @0x456)]
    #[expected_failure(abort_code = 327690, location = movedaoaddrx::errors)] // errors::permission_denied(not_admin()) = 327690
    fun test_non_admin_cannot_add_member(aptos_framework: &signer, alice: &signer, _bob: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, signer::address_of(alice));
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_addr = @0x123;
        let council_obj = dao_core::get_council_object(dao_addr);
        let non_admin = account::create_signer_for_test(@0x999);
        council::add_council_member_to_object(&non_admin, dao_addr, council_obj, @0x456);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123)]
    #[expected_failure(abort_code = 393316, location = movedaoaddrx::errors)] // errors::not_found_error(council_member_not_found()) = 393316
    fun test_min_members_constraint(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, signer::address_of(alice));
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_addr = @0x123;
        let council_obj = dao_core::get_council_object(dao_addr);
        
        // Trying to remove non-existent member should fail
        council::remove_council_member_from_object(alice, dao_addr, council_obj, @0x999);

        test_utils::destroy_caps(aptos_framework);
    }
}