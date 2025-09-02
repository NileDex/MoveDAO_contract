#[test_only]
module movedaoaddrx::membership_tests {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin;
    use movedaoaddrx::dao_core_file as dao_core;
    use movedaoaddrx::membership;
    use movedaoaddrx::staking;
    use movedaoaddrx::test_utils;

    const TEST_MEMBER: address = @0xA;
    const TEST_MEMBER2: address = @0xB;
    const TEST_MIN_STAKE: u64 = 100;

    #[test(aptos_framework = @0x1, admin = @movedaoaddrx)]
    fun test_membership_lifecycle(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();

        // Create DAO which initializes membership
        let initial_council = vector::singleton(@movedaoaddrx);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Description"), 
            b"logo", 
            b"bg",
            initial_council, 
            30
        );

        let dao_addr = signer::address_of(admin);

        // Create test member account
        let member1 = account::create_account_for_test(TEST_MEMBER);
        test_utils::setup_test_account(&member1);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(&member1);
        test_utils::mint_aptos(&member1, 1000);

        // Stake and join
        staking::stake(&member1, dao_addr, TEST_MIN_STAKE);
        membership::join(&member1, dao_addr);
        
        // Verify membership
        assert!(membership::is_member(dao_addr, TEST_MEMBER), 1);
        assert!(membership::total_members(dao_addr) == 1, 2);
        assert!(membership::get_voting_power(dao_addr, TEST_MEMBER) == TEST_MIN_STAKE, 3);

        // Stake more and verify voting power increases
        staking::stake(&member1, dao_addr, 500);
        assert!(membership::get_voting_power(dao_addr, TEST_MEMBER) == TEST_MIN_STAKE + 500, 4);

        // Leave and verify
        membership::leave(&member1, dao_addr);
        assert!(!membership::is_member(dao_addr, TEST_MEMBER), 5);
        assert!(membership::total_members(dao_addr) == 0, 6);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @movedaoaddrx)]
    #[expected_failure(abort_code = 524440, location = movedaoaddrx::errors)] // errors::already_exists_error(already_member()) = 524440
    fun test_cannot_join_twice(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();

        let initial_council = vector::singleton(@movedaoaddrx);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_addr = signer::address_of(admin);

        let member = account::create_account_for_test(TEST_MEMBER);
        test_utils::setup_test_account(&member);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(&member);
        test_utils::mint_aptos(&member, 1000);
        
        staking::stake(&member, dao_addr, TEST_MIN_STAKE);
        membership::join(&member, dao_addr);
        membership::join(&member, dao_addr);  // Should abort with EALREADY_MEMBER

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @movedaoaddrx)]
    #[expected_failure(abort_code = 153, location = movedaoaddrx::membership)] // errors::min_stake_required() = 153
    fun test_cannot_join_without_min_stake(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();

        let initial_council = vector::singleton(@movedaoaddrx);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_addr = signer::address_of(admin);

        let member = account::create_account_for_test(TEST_MEMBER);
        test_utils::setup_test_account(&member);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(&member);
        test_utils::mint_aptos(&member, 1000);
        
        // Try to join without staking - should abort
        membership::join(&member, dao_addr);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @movedaoaddrx)]
    fun test_voting_power_scales_with_stake(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();

        let initial_council = vector::singleton(@movedaoaddrx);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_addr = signer::address_of(admin);

        // Create test members
        let member1 = account::create_account_for_test(TEST_MEMBER);
        let member2 = account::create_account_for_test(TEST_MEMBER2);
        test_utils::setup_test_account(&member1);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(&member2);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(&member1);
        coin::register<aptos_coin::AptosCoin>(&member2);
        test_utils::mint_aptos(&member1, 5000);
        test_utils::mint_aptos(&member2, 3000);

        // Member 1 stakes and joins
        staking::stake(&member1, dao_addr, 1000);
        membership::join(&member1, dao_addr);
        assert!(membership::get_voting_power(dao_addr, TEST_MEMBER) == 1000, 1);

        // Member 2 stakes and joins
        staking::stake(&member2, dao_addr, 2000);
        membership::join(&member2, dao_addr);
        assert!(membership::get_voting_power(dao_addr, TEST_MEMBER2) == 2000, 2);

        // Member 1 stakes more
        staking::stake(&member1, dao_addr, 500);
        assert!(membership::get_voting_power(dao_addr, TEST_MEMBER) == 1500, 3);

        // Check total voting power
        assert!(membership::total_voting_power(dao_addr) == 3500, 4);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @movedaoaddrx)]
    fun test_voting_power_decreases_with_unstake(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();

        let initial_council = vector::singleton(@movedaoaddrx);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_addr = signer::address_of(admin);

        let member = account::create_account_for_test(TEST_MEMBER);
        test_utils::setup_test_account(&member);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(&member);
        test_utils::mint_aptos(&member, 5000);

        // Stake and join
        staking::stake(&member, dao_addr, 2000);
        membership::join(&member, dao_addr);
        assert!(membership::get_voting_power(dao_addr, TEST_MEMBER) == 2000, 1);

        // Unstake some amount
        staking::unstake(&member, dao_addr, 500);
        assert!(membership::get_voting_power(dao_addr, TEST_MEMBER) == 1500, 2);

        // Unstake more, but keep above minimum
        staking::unstake(&member, dao_addr, 1400);
        assert!(membership::is_member(dao_addr, TEST_MEMBER), 3);
        assert!(membership::get_voting_power(dao_addr, TEST_MEMBER) == 100, 4);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @movedaoaddrx)]
    #[expected_failure(abort_code = 327831, location = movedaoaddrx::errors)] // errors::permission_denied(not_member()) = 327831
    fun test_cannot_leave_if_not_member(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();

        let initial_council = vector::singleton(@movedaoaddrx);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_addr = signer::address_of(admin);

        let member = account::create_account_for_test(TEST_MEMBER);
        test_utils::setup_test_account(&member);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        
        // Try to leave without being a member - should abort
        membership::leave(&member, dao_addr);

        test_utils::destroy_caps(aptos_framework);
    }
}