#[test_only]
module dao_addr::treasury_test {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use dao_addr::dao_core;
    use dao_addr::treasury;
    use dao_addr::test_utils;

    const EASSERTION_FAILED: u64 = 1000;

    #[test(aptos_framework = @0x1, alice = @0x123)]
    fun test_initialize_only(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);

        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        // Treasury is initialized during DAO creation, so we just check the balance
        let dao_addr = signer::address_of(alice);
        let treasury_obj = dao_core::get_treasury_object(dao_addr);
        let balance = treasury::get_balance_from_object(treasury_obj);
        assert!(balance == 0, EASSERTION_FAILED);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123)]
    fun test_deposit_withdraw(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);

        coin::register<AptosCoin>(alice);
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_addr = signer::address_of(alice);

        test_utils::mint_aptos(alice, 1000);
        let treasury_obj = dao_core::get_treasury_object(dao_addr);
        treasury::deposit_to_object(alice, treasury_obj, 500);

        let balance = treasury::get_balance_from_object(treasury_obj);
        assert!(balance == 500, EASSERTION_FAILED + 1);

        treasury::withdraw_from_object(alice, dao_addr, treasury_obj, 200);
        let new_balance = treasury::get_balance_from_object(treasury_obj);
        assert!(new_balance == 300, EASSERTION_FAILED + 2);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123)]
    #[expected_failure(abort_code = 10, location = dao_addr::treasury)] // errors::not_admin() = 10
    fun test_non_admin_cannot_withdraw(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x999);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);

        coin::register<AptosCoin>(alice);
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_addr = signer::address_of(alice);

        test_utils::mint_aptos(alice, 1000);
        let treasury_obj = dao_core::get_treasury_object(dao_addr);
        treasury::deposit_to_object(alice, treasury_obj, 500);

        let non_admin = account::create_signer_for_test(@0x999);
        treasury::withdraw_from_object(&non_admin, dao_addr, treasury_obj, 200);  // Should fail with ENOT_ADMIN

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123)]
    fun test_multiple_deposits(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);

        coin::register<AptosCoin>(alice);
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_addr = signer::address_of(alice);

        test_utils::mint_aptos(alice, 2000);
        let treasury_obj = dao_core::get_treasury_object(dao_addr);
        treasury::deposit_to_object(alice, treasury_obj, 500);
        treasury::deposit_to_object(alice, treasury_obj, 300);
        let balance = treasury::get_balance_from_object(treasury_obj);
        assert!(balance == 800, EASSERTION_FAILED + 3);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123)]
    #[expected_failure] // Should fail when trying to withdraw more than balance
    fun test_cannot_withdraw_more_than_balance(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);

        coin::register<AptosCoin>(alice);
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_addr = signer::address_of(alice);

        test_utils::mint_aptos(alice, 1000);
        let treasury_obj = dao_core::get_treasury_object(dao_addr);
        treasury::deposit_to_object(alice, treasury_obj, 500);
        treasury::withdraw_from_object(alice, dao_addr, treasury_obj, 501);  // Should fail - insufficient balance

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123)]
    fun test_zero_deposit_withdraw(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);

        coin::register<AptosCoin>(alice);
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_addr = signer::address_of(alice);

        let treasury_obj = dao_core::get_treasury_object(dao_addr);
        
        // Test zero deposit
        treasury::deposit_to_object(alice, treasury_obj, 0);
        assert!(treasury::get_balance_from_object(treasury_obj) == 0, EASSERTION_FAILED + 4);

        test_utils::mint_aptos(alice, 100);
        treasury::deposit_to_object(alice, treasury_obj, 100);
        
        // Test zero withdraw
        treasury::withdraw_from_object(alice, dao_addr, treasury_obj, 0);
        assert!(treasury::get_balance_from_object(treasury_obj) == 100, EASSERTION_FAILED + 5);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123, depositor = @0x456)]
    fun test_anyone_can_deposit_only_admin_can_withdraw(aptos_framework: &signer, alice: &signer, depositor: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
        test_utils::setup_test_account(depositor);

        coin::register<AptosCoin>(alice);
        coin::register<AptosCoin>(depositor);
        
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_addr = signer::address_of(alice);

        let treasury_obj = dao_core::get_treasury_object(dao_addr);
        
        // Anyone can deposit
        test_utils::mint_aptos(depositor, 500);
        treasury::deposit_to_object(depositor, treasury_obj, 500);
        assert!(treasury::get_balance_from_object(treasury_obj) == 500, EASSERTION_FAILED + 6);

        // Only admin can withdraw
        treasury::withdraw_from_object(alice, dao_addr, treasury_obj, 100);
        assert!(treasury::get_balance_from_object(treasury_obj) == 400, EASSERTION_FAILED + 7);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123)]
    fun test_treasury_balance_persistence(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);

        coin::register<AptosCoin>(alice);
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_addr = signer::address_of(alice);

        let treasury_obj = dao_core::get_treasury_object(dao_addr);
        
        // Multiple operations should maintain correct balance
        test_utils::mint_aptos(alice, 1000);
        treasury::deposit_to_object(alice, treasury_obj, 300);
        assert!(treasury::get_balance_from_object(treasury_obj) == 300, EASSERTION_FAILED + 8);

        treasury::withdraw_from_object(alice, dao_addr, treasury_obj, 50);
        assert!(treasury::get_balance_from_object(treasury_obj) == 250, EASSERTION_FAILED + 9);

        treasury::deposit_to_object(alice, treasury_obj, 150);
        assert!(treasury::get_balance_from_object(treasury_obj) == 400, EASSERTION_FAILED + 10);

        treasury::withdraw_from_object(alice, dao_addr, treasury_obj, 400);
        assert!(treasury::get_balance_from_object(treasury_obj) == 0, EASSERTION_FAILED + 11);

        test_utils::destroy_caps(aptos_framework);
    }
}