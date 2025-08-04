#[test_only]
module dao_addr::admin_tests {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use dao_addr::dao_core;
    use dao_addr::admin;
    use dao_addr::test_utils;

    const EASSERTION_FAILED: u64 = 200;

    #[test(aptos_framework = @0x1, alice = @dao_addr)]
    fun test_admin_initialization(aptos_framework: &signer, alice: &signer) {
        // Setup framework and test accounts
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@dao_addr);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Initialize test environment
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
        coin::register<aptos_coin::AptosCoin>(alice);

        // Create DAO - this will initialize the admin system
        let initial_council = vector::empty();
        vector::push_back(&mut initial_council, signer::address_of(alice));
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

        // Get the DAO address (where admin data is stored)
        let dao_addr = signer::address_of(alice);
        
        // Verify admin initialization - the creator should be a super admin
        assert!(admin::is_admin(dao_addr, dao_addr), EASSERTION_FAILED);
        assert!(
            admin::get_admin_role(dao_addr, dao_addr) == admin::role_super_admin(),
            EASSERTION_FAILED + 1
        );

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @dao_addr, bob = @0x456)]
    fun test_add_and_remove_admin(aptos_framework: &signer, alice: &signer, bob: &signer) {
        // Setup accounts
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@dao_addr);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Initialize test environment
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
        test_utils::setup_test_account(bob);
        coin::register<aptos_coin::AptosCoin>(alice);

        // Create DAO with alice as initial council member
        let initial_council = vector::empty();
        vector::push_back(&mut initial_council, signer::address_of(alice));
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

        let dao_addr = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);

        // Test adding admin
        admin::add_admin(alice, dao_addr, bob_addr, admin::role_standard(), 0);
        assert!(admin::is_admin(dao_addr, bob_addr), EASSERTION_FAILED);
        assert!(
            admin::get_admin_role(dao_addr, bob_addr) == admin::role_standard(),
            EASSERTION_FAILED + 1
        );
        
        // Check admin list contains both admins
        let admins = admin::get_admins(dao_addr);
        assert!(vector::length(&admins) == 2, EASSERTION_FAILED + 2);
        
        // Test removing admin
        admin::remove_admin(alice, dao_addr, bob_addr);
        assert!(!admin::is_admin(dao_addr, bob_addr), EASSERTION_FAILED + 3);

        // Admin list should only have 1 admin now
        let admins_after = admin::get_admins(dao_addr);
        assert!(vector::length(&admins_after) == 1, EASSERTION_FAILED + 4);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @dao_addr)]
    #[expected_failure(abort_code = 11, location = dao_addr::admin)] // errors::invalid_role() = 11
    fun test_invalid_role_rejected(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@dao_addr);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty();
        vector::push_back(&mut initial_council, signer::address_of(alice));
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

        let dao_addr = signer::address_of(alice);
        // Try to add admin with invalid role - should fail
        admin::add_admin(alice, dao_addr, @0x999, 42, 0); // Invalid role = 42

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @dao_addr, bob = @0x456)]
    #[expected_failure(abort_code = 327690, location = dao_addr::errors)] // errors::permission_denied(not_admin()) = 327690
    fun test_non_admin_cannot_add_admin(aptos_framework: &signer, alice: &signer, bob: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@dao_addr);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
        test_utils::setup_test_account(bob);
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty();
        vector::push_back(&mut initial_council, signer::address_of(alice));
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

        let dao_addr = signer::address_of(alice);
        // Bob (non-admin) tries to add someone as admin - should fail
        admin::add_admin(bob, dao_addr, @0x999, admin::role_standard(), 0);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @dao_addr, bob = @0x456)]
    fun test_temporary_admin_expiration(aptos_framework: &signer, alice: &signer, bob: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@dao_addr);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
        test_utils::setup_test_account(bob);
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty();
        vector::push_back(&mut initial_council, signer::address_of(alice));
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

        let dao_addr = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);

        // Add temporary admin that expires in 100 seconds
        admin::add_admin(alice, dao_addr, bob_addr, admin::role_temporary(), 100);
        assert!(admin::is_admin(dao_addr, bob_addr), EASSERTION_FAILED);
        
        // Fast forward time past expiration
        timestamp::fast_forward_seconds(101);
        
        // Admin should no longer be valid due to expiration
        assert!(!admin::is_admin(dao_addr, bob_addr), EASSERTION_FAILED + 1);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @dao_addr)]
    #[expected_failure(abort_code = 12, location = dao_addr::admin)] // errors::expiration_past() = 12
    fun test_cannot_add_admin_with_past_expiration(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@dao_addr);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty();
        vector::push_back(&mut initial_council, signer::address_of(alice));
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

        let dao_addr = signer::address_of(alice);
        // Try to add admin with expiration in the past (1 second) - should fail
        admin::add_admin(alice, dao_addr, @0x999, admin::role_temporary(), 1);

        test_utils::destroy_caps(aptos_framework);
    }
}