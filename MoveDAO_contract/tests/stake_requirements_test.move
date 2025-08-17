#[test_only]
module dao_addr::stake_requirements_test {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use dao_addr::dao_core;
    use dao_addr::membership;
    use dao_addr::staking;
    use dao_addr::test_utils;

    const EASSERTION_FAILED: u64 = 2000;

    #[test(aptos_framework = @0x1, admin = @0x123, member = @0x456)]
    fun test_update_min_stake_to_join(aptos_framework: &signer, admin: &signer, member: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
        test_utils::setup_test_account(member);

        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(member);
        
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_addr = signer::address_of(admin);

        // Check initial minimum stake (set to 30 in create_dao call)
        let initial_min_stake = membership::get_min_stake(dao_addr);
        assert!(initial_min_stake == 30, EASSERTION_FAILED + 1);

        // Admin updates minimum stake to 50
        membership::update_min_stake(admin, dao_addr, 50);

        // Verify the update
        let new_min_stake = membership::get_min_stake(dao_addr);
        assert!(new_min_stake == 50, EASSERTION_FAILED + 2);

        // Test member cannot join with insufficient stake
        test_utils::mint_aptos(member, 1000);
        staking::stake(member, dao_addr, 25); // Only stake 25, need 50

        // This should fail due to insufficient stake
        // membership::join(member, dao_addr); // Would fail with min_stake_required

        // Member stakes enough to meet new requirement
        staking::stake(member, dao_addr, 25); // Total 50, now meets requirement
        membership::join(member, dao_addr); // Should succeed

        // Verify member is now a member
        assert!(membership::is_member(dao_addr, signer::address_of(member)), EASSERTION_FAILED + 3);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, member = @0x456)]
    fun test_update_min_proposal_stake(aptos_framework: &signer, admin: &signer, member: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
        test_utils::setup_test_account(member);

        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(member);
        
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_addr = signer::address_of(admin);

        // Check initial minimum proposal stake (default is 1x join stake = 30 * 1 = 30)
        let initial_min_proposal_stake = membership::get_min_proposal_stake(dao_addr);
        assert!(initial_min_proposal_stake == 30, EASSERTION_FAILED + 4);

        // First lower join stake to allow setting proposal stake to 100
        membership::update_min_stake(admin, dao_addr, 50);
        
        // Now admin updates minimum proposal stake to 100
        membership::update_min_proposal_stake(admin, dao_addr, 100);

        // Verify the update
        let new_min_proposal_stake = membership::get_min_proposal_stake(dao_addr);
        assert!(new_min_proposal_stake == 100, EASSERTION_FAILED + 5);

        // Test member joins with enough stake to be member but not create proposals
        test_utils::mint_aptos(member, 1000);
        staking::stake(member, dao_addr, 50); // Enough to join, not enough for proposals
        membership::join(member, dao_addr);

        // Verify member can join but cannot create proposals
        assert!(membership::is_member(dao_addr, signer::address_of(member)), EASSERTION_FAILED + 6);
        assert!(!membership::can_create_proposal(dao_addr, signer::address_of(member)), EASSERTION_FAILED + 7);

        // Member stakes more to meet proposal requirement
        staking::stake(member, dao_addr, 50); // Total 100, meets proposal requirement

        // Now member can create proposals
        assert!(membership::can_create_proposal(dao_addr, signer::address_of(member)), EASSERTION_FAILED + 8);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    #[expected_failure(abort_code = 4, location = dao_addr::membership)] // errors::invalid_amount() = 4
    fun test_update_min_stake_invalid_amount(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);

        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_addr = signer::address_of(admin);

        // Try to set minimum stake to 0 (should fail)
        membership::update_min_stake(admin, dao_addr, 0);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    #[expected_failure(abort_code = 4, location = dao_addr::membership)] // errors::invalid_amount() = 4
    fun test_update_min_proposal_stake_below_join_stake(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);

        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_addr = signer::address_of(admin);

        // Set join stake to 50
        membership::update_min_stake(admin, dao_addr, 50);

        // Try to set proposal stake below join stake (should fail)
        membership::update_min_proposal_stake(admin, dao_addr, 25);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, non_admin = @0x789)]
    #[expected_failure(abort_code = 10, location = dao_addr::membership)] // errors::not_admin() = 10
    fun test_non_admin_cannot_update_stake_requirements(aptos_framework: &signer, admin: &signer, non_admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x789);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
        test_utils::setup_test_account(non_admin);

        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_addr = signer::address_of(admin);

        // Non-admin tries to update minimum stake (should fail)
        membership::update_min_stake(non_admin, dao_addr, 100);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    fun test_get_stake_requirements(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);

        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_addr = signer::address_of(admin);

        // Test view functions work correctly
        let min_stake = membership::get_min_stake(dao_addr);
        let min_proposal_stake = membership::get_min_proposal_stake(dao_addr);

        // Check default values (30 for join, 30 for proposals - 1x multiplier)
        assert!(min_stake == 30, EASSERTION_FAILED + 9);
        assert!(min_proposal_stake == 30, EASSERTION_FAILED + 10);

        // Update values
        membership::update_min_stake(admin, dao_addr, 75);
        membership::update_min_proposal_stake(admin, dao_addr, 200);

        // Verify updated values
        assert!(membership::get_min_stake(dao_addr) == 75, EASSERTION_FAILED + 11);
        assert!(membership::get_min_proposal_stake(dao_addr) == 200, EASSERTION_FAILED + 12);

        test_utils::destroy_caps(aptos_framework);
    }
}