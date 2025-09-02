#[test_only]
module movedaoaddrx::rewards_test {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use movedaoaddrx::dao_core_file;
    use movedaoaddrx::rewards;
    use movedaoaddrx::proposal;
    use movedaoaddrx::membership;
    use movedaoaddrx::staking;
    use movedaoaddrx::treasury;
    use movedaoaddrx::test_utils;

    const EASSERTION_FAILED: u64 = 1000;
    const TEST_DAO_ADMIN: address = @0x123;
    const TEST_VOTER1: address = @0x456;
    const TEST_VOTER2: address = @0x789;

    fun setup_dao_with_rewards(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        let council = vector::singleton(admin_addr);  // Use actual admin address
        dao_core_file::init_registry_for_test();
        dao_core_file::create_dao(
            admin,
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"),
            string::utf8(b"Test Description"),
            b"logo",
            b"bg",
            council,
            6000000 // min_stake_to_join (6 Move)
        );
    }

    fun setup_test_user(user: &signer, amount: u64) {
        test_utils::setup_test_account(user);
        coin::register<AptosCoin>(user);
        test_utils::mint_aptos(user, amount);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, voter1 = @0x456, voter2 = @0x789)]
    fun test_voting_rewards(
        aptos_framework: &signer,
        admin: &signer,
        voter1: &signer,
        voter2: &signer
    ) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(voter1));
        account::create_account_for_test(signer::address_of(voter2));
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 100000000000);  // 1000 APT
        setup_test_user(voter1, 100000000000);  // 1000 APT
        setup_test_user(voter2, 100000000000);  // 1000 APT

        setup_dao_with_rewards(admin);
        let dao_addr = signer::address_of(admin);

        // Add funds to treasury for rewards
        let treasury_obj = dao_core_file::get_treasury_object(dao_addr);
        treasury::deposit_to_object(admin, treasury_obj, 10000000000);  // 100 APT for rewards

        // Setup voters as members
        staking::stake(voter1, dao_addr, 200);
        staking::stake(voter2, dao_addr, 200);
        membership::join(voter1, dao_addr);
        membership::join(voter2, dao_addr);

        // Create a proposal
        proposal::create_proposal(
            admin,
            dao_addr,
            string::utf8(b"Test Proposal"),
            string::utf8(b"Description"),
            1,
            7200,
            30,
            50
        );

        // Start voting
        proposal::start_voting(admin, dao_addr, 0);

        // Cast votes (this should trigger voting rewards)
        proposal::cast_vote(voter1, dao_addr, 0, 1); // vote_yes
        proposal::cast_vote(voter2, dao_addr, 0, 2); // vote_no

        // Check pending rewards
        let voter1_addr = signer::address_of(voter1);
        let voter2_addr = signer::address_of(voter2);
        let voter1_rewards = rewards::get_pending_rewards(dao_addr, voter1_addr);
        let voter2_rewards = rewards::get_pending_rewards(dao_addr, voter2_addr);
        
        assert!(vector::length(&voter1_rewards) == 1, EASSERTION_FAILED);
        assert!(vector::length(&voter2_rewards) == 1, EASSERTION_FAILED);

        // Check claimable amounts
        let voter1_claimable = rewards::get_total_claimable(dao_addr, voter1_addr);
        let voter2_claimable = rewards::get_total_claimable(dao_addr, voter2_addr);
        
        assert!(voter1_claimable == 10, EASSERTION_FAILED + 1); // Default voting reward is 10
        assert!(voter2_claimable == 10, EASSERTION_FAILED + 2);

        // Claim rewards
        dao_core_file::claim_rewards(voter1, dao_addr);
        dao_core_file::claim_rewards(voter2, dao_addr);

        // Check claimed amounts
        let voter1_claimed = rewards::get_total_claimed(dao_addr, TEST_VOTER1);
        let voter2_claimed = rewards::get_total_claimed(dao_addr, TEST_VOTER2);
        
        assert!(voter1_claimed == 10, EASSERTION_FAILED + 3);
        assert!(voter2_claimed == 10, EASSERTION_FAILED + 4);

        // Check that claimable is now 0
        assert!(rewards::get_total_claimable(dao_addr, TEST_VOTER1) == 0, EASSERTION_FAILED + 5);
        assert!(rewards::get_total_claimable(dao_addr, TEST_VOTER2) == 0, EASSERTION_FAILED + 6);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    fun test_proposal_creation_reward(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 100000000000);  // 1000 APT

        setup_dao_with_rewards(admin);
        let dao_addr = signer::address_of(admin);

        // Add funds to treasury for rewards
        let treasury_obj = dao_core_file::get_treasury_object(dao_addr);
        treasury::deposit_to_object(admin, treasury_obj, 10000000000);  // 100 APT for rewards

        // Create a proposal (this should trigger proposal creation reward)
        proposal::create_proposal(
            admin,
            dao_addr,
            string::utf8(b"Test Proposal"),
            string::utf8(b"Description"),
            1,
            7200,
            30,
            50
        );

        // Check pending rewards for proposal creator
        let admin_addr = signer::address_of(admin);
        let admin_rewards = rewards::get_pending_rewards(dao_addr, admin_addr);
        assert!(vector::length(&admin_rewards) == 1, EASSERTION_FAILED);

        let admin_claimable = rewards::get_total_claimable(dao_addr, admin_addr);
        assert!(admin_claimable == 100, EASSERTION_FAILED + 1); // Default proposal creation reward is 100

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, voter1 = @0x456)]
    fun test_successful_proposal_reward(
        aptos_framework: &signer,
        admin: &signer,
        voter1: &signer
    ) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        account::create_account_for_test(TEST_VOTER1);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 100000000000);  // 1000 APT
        setup_test_user(voter1, 100000000000);  // 1000 APT

        setup_dao_with_rewards(admin);
        let dao_addr = signer::address_of(admin);

        // Add funds to treasury for rewards
        let treasury_obj = dao_core_file::get_treasury_object(dao_addr);
        treasury::deposit_to_object(admin, treasury_obj, 10000000000);  // 100 APT for rewards

        // Setup voter as member
        staking::stake(voter1, dao_addr, 200);
        membership::join(voter1, dao_addr);

        // Create a proposal
        proposal::create_proposal(
            admin,
            dao_addr,
            string::utf8(b"Test Proposal"),
            string::utf8(b"Description"),
            2,
            7200,
            30,
            50
        );

        // Start voting
        proposal::start_voting(admin, dao_addr, 0);

        // Wait for voting period to start (advance to voting start time)
        timestamp::fast_forward_seconds(2);

        // Cast a yes vote to make it pass
        proposal::cast_vote(voter1, dao_addr, 0, 1); // vote_yes

        // Fast forward past voting period
        timestamp::fast_forward_seconds(7200);

        // Finalize proposal (this should trigger successful proposal reward)
        proposal::finalize_proposal(admin, dao_addr, 0);

        // Check rewards - should have both proposal creation (100) and success (500) rewards
        let admin_claimable = rewards::get_total_claimable(dao_addr, TEST_DAO_ADMIN);
        assert!(admin_claimable == 600, EASSERTION_FAILED); // 100 + 500

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    fun test_reward_config_management(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 100000000000);  // 1000 APT

        setup_dao_with_rewards(admin);
        let dao_addr = signer::address_of(admin);

        // Check initial config
        let (voting_reward, proposal_reward, success_reward, staking_rate, total_distributed, enabled) = 
            rewards::get_reward_config(dao_addr);
        
        assert!(voting_reward == 10, EASSERTION_FAILED);
        assert!(proposal_reward == 100, EASSERTION_FAILED + 1);
        assert!(success_reward == 500, EASSERTION_FAILED + 2);
        assert!(staking_rate == 500, EASSERTION_FAILED + 3);
        assert!(total_distributed == 0, EASSERTION_FAILED + 4);
        assert!(enabled == true, EASSERTION_FAILED + 5);

        // Update config
        rewards::update_reward_config(admin, dao_addr, 20, 200, 1000, 1000);

        // Check updated config
        let (new_voting_reward, new_proposal_reward, new_success_reward, new_staking_rate, _, _) = 
            rewards::get_reward_config(dao_addr);
        
        assert!(new_voting_reward == 20, EASSERTION_FAILED + 6);
        assert!(new_proposal_reward == 200, EASSERTION_FAILED + 7);
        assert!(new_success_reward == 1000, EASSERTION_FAILED + 8);
        assert!(new_staking_rate == 1000, EASSERTION_FAILED + 9);

        // Test disabling rewards
        rewards::toggle_rewards(admin, dao_addr, false);
        let (_, _, _, _, _, enabled_after_toggle) = rewards::get_reward_config(dao_addr);
        assert!(enabled_after_toggle == false, EASSERTION_FAILED + 10);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    fun test_staking_rewards_distribution(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 100000000000);  // 1000 APT

        setup_dao_with_rewards(admin);
        let dao_addr = signer::address_of(admin);

        // Add funds to treasury for rewards
        let treasury_obj = dao_core_file::get_treasury_object(dao_addr);
        treasury::deposit_to_object(admin, treasury_obj, 10000000000);  // 100 APT for rewards

        // Test manual staking rewards distribution
        let stakers = vector::singleton(TEST_DAO_ADMIN);
        let amounts = vector::singleton(100000u64); // Use larger amount for visible rewards
        
        // Fast forward time to simulate longer staking period
        timestamp::fast_forward_seconds(86400 * 30); // 30 days
        
        rewards::distribute_staking_rewards(admin, dao_addr, stakers, amounts);

        // Check if rewards were distributed
        let admin_claimable = rewards::get_total_claimable(dao_addr, TEST_DAO_ADMIN);
        // Calculation: (100000 * 500 * 86400 * 30) / (365 * 24 * 3600 * 10000) = ~41
        assert!(admin_claimable > 0, EASSERTION_FAILED);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, voter1 = @0x456)]
    #[expected_failure(abort_code = 400, location = movedaoaddrx::dao_core_file)] // errors::insufficient_treasury() = 400
    fun test_insufficient_treasury_for_rewards(
        aptos_framework: &signer,
        admin: &signer,
        voter1: &signer
    ) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        account::create_account_for_test(TEST_VOTER1);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 100000000000);  // 1000 APT
        setup_test_user(voter1, 100000000000);  // 1000 APT

        setup_dao_with_rewards(admin);
        let dao_addr = signer::address_of(admin);

        // Don't add funds to treasury - should fail when claiming

        // Setup voter as member
        staking::stake(voter1, dao_addr, 200);
        membership::join(voter1, dao_addr);

        // Create a proposal
        proposal::create_proposal(
            admin,
            dao_addr,
            string::utf8(b"Test Proposal"),
            string::utf8(b"Description"),
            1,
            7200,
            30,
            50
        );

        // Start voting and cast vote
        proposal::start_voting(admin, dao_addr, 0);
        proposal::cast_vote(voter1, dao_addr, 0, 1); // vote_yes

        // Try to claim rewards - should fail due to insufficient treasury
        dao_core_file::claim_rewards(voter1, dao_addr);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = movedaoaddrx::dao_core_file)] // errors::nothing_to_claim() = 1
    fun test_cannot_claim_when_nothing_to_claim_expected_failure() {
        let aptos_framework = account::create_signer_for_test(@0x1);
        let dao_admin = account::create_signer_for_test(@movedaoaddrx);
        let user = account::create_signer_for_test(@0xA11CE);

        // Setup
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        account::create_account_for_test(@0xA11CE);

        test_utils::setup_aptos(&aptos_framework);
        test_utils::setup_test_account(&dao_admin);
        test_utils::setup_test_account(&user);
        coin::register<AptosCoin>(&user);
        test_utils::mint_aptos(&user, 1000);
        dao_core_file::init_registry_for_test();

        // Create DAO
        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, signer::address_of(&dao_admin));
        dao_core_file::create_dao(
            &dao_admin,
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"),
            string::utf8(b"Description"),
            b"logo",
            b"bg",
            initial_council,
            30
        );

        // Make user stake first, then join as member
        staking::stake(&user, @movedaoaddrx, 1000);
        membership::join(&user, @movedaoaddrx);

        // Try to claim rewards when user has no rewards
        // This should fail with nothing_to_claim error
        dao_core_file::claim_rewards(&user, @movedaoaddrx);
    }
}