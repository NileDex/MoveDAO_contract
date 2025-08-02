#[test_only]
module dao_addr::council_tests {
    use std::vector;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use dao_addr::dao_core;
    use dao_addr::council;
    use dao_addr::test_utils;

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
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty<address>();
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30, 
            3600, 
            86400
        );

        let dao_addr = @0x123;
        let council_obj = dao_core::get_council_object(dao_addr);
        
        // Add first member
        council::add_council_member_to_object(alice, council_obj, @0x456);
        let members1 = council::get_council_members_from_object(council_obj);
        assert!(vector::length(&members1) == 1, EASSERTION_FAILED);
        assert!(vector::contains(&members1, &@0x456), EASSERTION_FAILED + 1);

        // Add second member
        council::add_council_member_to_object(alice, council_obj, @0x789);
        let members2 = council::get_council_members_from_object(council_obj);
        assert!(vector::length(&members2) == 2, EASSERTION_FAILED + 2);
        assert!(vector::contains(&members2, &@0x789), EASSERTION_FAILED + 3);

        // Remove first member
        council::remove_council_member_from_object(alice, council_obj, @0x456);
        let members3 = council::get_council_members_from_object(council_obj);
        assert!(vector::length(&members3) == 1, EASSERTION_FAILED + 4);
        assert!(!vector::contains(&members3, &@0x456), EASSERTION_FAILED + 5);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123, _bob = @0x456)]
    #[expected_failure(abort_code = 65537, location = dao_addr::council)] // ENOT_ADMIN (65537 = 0x10001)
    fun test_non_admin_cannot_add_member(aptos_framework: &signer, alice: &signer, _bob: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty<address>();
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30, 
            3600, 
            86400
        );

        let dao_addr = @0x123;
        let council_obj = dao_core::get_council_object(dao_addr);
        let non_admin = account::create_signer_for_test(@0x999);
        council::add_council_member_to_object(&non_admin, council_obj, @0x456);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123)]
    #[expected_failure(abort_code = 65538, location = dao_addr::council)] // ECOUNCIL_MEMBER_NOT_FOUND (65538 = 0x10002)
    fun test_min_members_constraint(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty<address>();
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30, 
            3600, 
            86400
        );

        let dao_addr = @0x123;
        let council_obj = dao_core::get_council_object(dao_addr);
        
        // Trying to remove non-existent member should fail
        council::remove_council_member_from_object(alice, council_obj, @0x999);

        test_utils::destroy_caps(aptos_framework);
    }
}