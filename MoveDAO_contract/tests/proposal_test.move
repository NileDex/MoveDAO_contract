#[test_only]
module dao_addr::proposal_tests {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use dao_addr::dao_core;
    use dao_addr::proposal;
    use dao_addr::membership;
    use dao_addr::staking;
    use dao_addr::test_utils;

    const PROPOSER: address = @0xA11CE;
    const VOTER1: address = @0xB0B;
    const VOTER2: address = @0xC0DE;
    const EASSERTION_FAILED: u64 = 1000;

    fun setup_dao(aptos_framework: &signer, dao_admin: &signer): address {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        account::create_account_for_test(@0x1);
        account::create_account_for_test(@dao_addr);
        account::create_account_for_test(PROPOSER);
        account::create_account_for_test(VOTER1);
        account::create_account_for_test(VOTER2);

        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(dao_admin);

        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, signer::address_of(dao_admin));
        dao_core::create_dao(
            dao_admin,
            string::utf8(b"Test DAO"),
            string::utf8(b"Description"),
            b"logo",
            b"bg", 
            initial_council,
            30,
            3600,
            86400
        );

        // Get the actual DAO address where data is stored
        let dao_addr = signer::address_of(dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);
        let voter2 = account::create_signer_for_test(VOTER2);

        test_utils::setup_test_account(&proposer);
        test_utils::setup_test_account(&voter1);
        test_utils::setup_test_account(&voter2);
        coin::register<aptos_coin::AptosCoin>(&proposer);
        coin::register<aptos_coin::AptosCoin>(&voter1);
        coin::register<aptos_coin::AptosCoin>(&voter2);

        test_utils::mint_aptos(&proposer, 1000);
        test_utils::mint_aptos(&voter1, 1000);
        test_utils::mint_aptos(&voter2, 1000);

        staking::stake(&proposer, dao_addr, 100);
        staking::stake(&voter1, dao_addr, 100);
        staking::stake(&voter2, dao_addr, 100);

        membership::join(&proposer, dao_addr);
        membership::join(&voter1, dao_addr);
        membership::join(&voter2, dao_addr);

        dao_addr
    }

    #[test(aptos_framework = @0x1, dao_admin = @dao_addr)]
    fun test_proposal_quorum_requirements(aptos_framework: &signer, dao_admin: &signer) {
        let dao_addr = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);
        let voter2 = account::create_signer_for_test(VOTER2);

        // Create proposal with 75% quorum requirement
        // Total staked = 300 (100 each for 3 members)
        // Need 225 votes to meet quorum (75% of 300)
        proposal::create_proposal(
            &proposer,
            dao_addr,
            string::utf8(b"High Quorum Proposal"),
            string::utf8(b"Needs more votes"),
            3600,
            3600,
            75
        );
        proposal::start_voting(&proposer, dao_addr, 0);

        // Cast votes - total 200 votes (proposer + voter1)
        // This is 66.66% of total staked - below 75% requirement
        proposal::cast_vote(&proposer, dao_addr, 0, 1); // vote_yes
        proposal::cast_vote(&voter1, dao_addr, 0, 1); // vote_yes

        // Finalize - should reject due to quorum not met
        timestamp::fast_forward_seconds(3601);
        proposal::finalize_proposal(dao_admin, dao_addr, 0);
        assert!(proposal::get_proposal_status(dao_addr, 0) == 3, EASSERTION_FAILED + 1); // status_rejected

        // Create another proposal with 50% quorum that should pass
        proposal::create_proposal(
            &proposer,
            dao_addr,
            string::utf8(b"Lower Quorum Proposal"),
            string::utf8(b"Should pass quorum"),
            3600,
            3600,
            50
        );
        proposal::start_voting(&proposer, dao_addr, 1);

        // Cast votes - total 200 votes meets 50% of 300 requirement
        proposal::cast_vote(&proposer, dao_addr, 1, 1); // vote_yes
        proposal::cast_vote(&voter1, dao_addr, 1, 2); // vote_no

        // Finalize - should pass quorum but reject due to votes (tie broken by no votes)
        timestamp::fast_forward_seconds(3601);
        proposal::finalize_proposal(dao_admin, dao_addr, 1);
        assert!(proposal::get_proposal_status(dao_addr, 1) == 3, EASSERTION_FAILED + 2); // status_rejected

        // Create third proposal with 50% quorum that should pass
        proposal::create_proposal(
            &proposer,
            dao_addr,
            string::utf8(b"Passing Proposal"),
            string::utf8(b"Should pass"),
            3600,
            3600,
            50
        );
        proposal::start_voting(&proposer, dao_addr, 2);

        // Cast votes - total 200 votes meets 50% of 300 requirement
        proposal::cast_vote(&proposer, dao_addr, 2, 1); // vote_yes
        proposal::cast_vote(&voter2, dao_addr, 2, 1); // vote_yes

        // Finalize - should pass both quorum and vote majority
        timestamp::fast_forward_seconds(3601);
        proposal::finalize_proposal(dao_admin, dao_addr, 2);
        assert!(proposal::get_proposal_status(dao_addr, 2) == 2, EASSERTION_FAILED + 3); // status_passed

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @dao_addr)]
    fun test_proposal_lifecycle(aptos_framework: &signer, dao_admin: &signer) {
        let dao_addr = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);
        let voter2 = account::create_signer_for_test(VOTER2);

        timestamp::fast_forward_seconds(1000);
        proposal::create_proposal(
            &proposer,
            dao_addr,
            string::utf8(b"Upgrade Protocol"),
            string::utf8(b"Change fee structure"),
            86400,
            86400,
            30
        );

        assert!(proposal::get_proposal_status(dao_addr, 0) == 0, EASSERTION_FAILED + 4); // status_draft
        proposal::start_voting(&proposer, dao_addr, 0);
        assert!(proposal::get_proposal_status(dao_addr, 0) == 1, EASSERTION_FAILED + 5); // status_active

        timestamp::fast_forward_seconds(1);
        proposal::cast_vote(&voter1, dao_addr, 0, 1); // vote_yes
        proposal::cast_vote(&voter2, dao_addr, 0, 2); // vote_no

        timestamp::fast_forward_seconds(86401);
        proposal::finalize_proposal(dao_admin, dao_addr, 0);
        assert!(proposal::get_proposal_status(dao_addr, 0) == 3, EASSERTION_FAILED + 6); // status_rejected

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @dao_addr)]
    #[expected_failure(abort_code = 6, location = dao_addr::proposal)] // errors::invalid_status() = 6
    fun test_cannot_vote_before_voting_period(aptos_framework: &signer, dao_admin: &signer) {
        let dao_addr = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);

        proposal::create_proposal(
            &proposer,
            dao_addr,
            string::utf8(b"Early Voting Test"),
            string::utf8(b"Test early voting"),
            3600,
            3600,
            30
        );

        // Try to vote on draft proposal (not started yet) - should fail
        proposal::cast_vote(&voter1, dao_addr, 0, 1); // vote_yes
        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @dao_addr)]
    fun test_successful_proposal_execution(aptos_framework: &signer, dao_admin: &signer) {
        let dao_addr = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);
        let voter2 = account::create_signer_for_test(VOTER2);

        proposal::create_proposal(
            &proposer,
            dao_addr,
            string::utf8(b"Successful Proposal"),
            string::utf8(b"This should pass"),
            3600,
            3600,
            50
        );
        proposal::start_voting(&proposer, dao_addr, 0);

        proposal::cast_vote(&proposer, dao_addr, 0, 1); // vote_yes
        proposal::cast_vote(&voter1, dao_addr, 0, 1); // vote_yes
        proposal::cast_vote(&voter2, dao_addr, 0, 2); // vote_no

        timestamp::fast_forward_seconds(3601);
        proposal::finalize_proposal(dao_admin, dao_addr, 0);
        assert!(proposal::get_proposal_status(dao_addr, 0) == 2, EASSERTION_FAILED + 7); // status_passed

        proposal::execute_proposal(dao_admin, dao_addr, 0);
        assert!(proposal::get_proposal_status(dao_addr, 0) == 4, EASSERTION_FAILED + 8); // status_executed

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @dao_addr)]
    #[expected_failure(abort_code = 9, location = dao_addr::proposal)] // errors::not_authorized() = 9
    fun test_non_member_proposal_fails(aptos_framework: &signer, dao_admin: &signer) {
        let dao_addr = setup_dao(aptos_framework, dao_admin);

        let non_member = account::create_signer_for_test(@0xDEAD);
        account::create_account_for_test(@0xDEAD);

        proposal::create_proposal(
            &non_member,
            dao_addr,
            string::utf8(b"Should Fail"),
            string::utf8(b"Non-member proposal"),
            3600,
            3600,
            30
        );

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @dao_addr)]
    #[expected_failure(abort_code = 202, location = dao_addr::proposal)] // errors::already_voted() = 202
    fun test_cannot_vote_twice(aptos_framework: &signer, dao_admin: &signer) {
        let dao_addr = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);

        proposal::create_proposal(
            &proposer,
            dao_addr,
            string::utf8(b"Double Vote Test"),
            string::utf8(b"Test double voting"),
            3600,
            3600,
            30
        );
        proposal::start_voting(&proposer, dao_addr, 0);

        proposal::cast_vote(&voter1, dao_addr, 0, 1); // vote_yes
        proposal::cast_vote(&voter1, dao_addr, 0, 2); // vote_no - Should fail

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @dao_addr)]
    #[expected_failure(abort_code = 201, location = dao_addr::proposal)] // errors::voting_ended() = 201
    fun test_cannot_vote_after_deadline(aptos_framework: &signer, dao_admin: &signer) {
        let dao_addr = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);

        proposal::create_proposal(
            &proposer,
            dao_addr,
            string::utf8(b"Late Vote Test"),
            string::utf8(b"Test late voting"),
            3600,
            3600,
            30
        );
        proposal::start_voting(&proposer, dao_addr, 0);

        // Fast forward past voting deadline
        timestamp::fast_forward_seconds(3601);
        
        // Try to vote after deadline - should fail
        proposal::cast_vote(&voter1, dao_addr, 0, 1); // vote_yes

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @dao_addr)]
    fun test_proposal_cancellation(aptos_framework: &signer, dao_admin: &signer) {
        let dao_addr = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);

        proposal::create_proposal(
            &proposer,
            dao_addr,
            string::utf8(b"Cancellable Proposal"),
            string::utf8(b"This will be cancelled"),
            3600,
            3600,
            30
        );

        // Cancel draft proposal
        proposal::cancel_proposal(&proposer, dao_addr, 0);
        assert!(proposal::get_proposal_status(dao_addr, 0) == 5, EASSERTION_FAILED + 9); // status_cancelled

        // Create another proposal and cancel during active voting
        proposal::create_proposal(
            &proposer,
            dao_addr,
            string::utf8(b"Active Cancellable"),
            string::utf8(b"Cancel during voting"),
            3600,
            3600,
            30
        );
        proposal::start_voting(&proposer, dao_addr, 1);
        
        proposal::cancel_proposal(&proposer, dao_addr, 1);
        assert!(proposal::get_proposal_status(dao_addr, 1) == 5, EASSERTION_FAILED + 10); // status_cancelled

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @dao_addr)]
    fun test_proposals_count(aptos_framework: &signer, dao_admin: &signer) {
        let dao_addr = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);

        assert!(proposal::get_proposals_count(dao_addr) == 0, EASSERTION_FAILED + 11);

        proposal::create_proposal(
            &proposer,
            dao_addr,
            string::utf8(b"First Proposal"),
            string::utf8(b"First one"),
            3600,
            3600,
            30
        );
        assert!(proposal::get_proposals_count(dao_addr) == 1, EASSERTION_FAILED + 12);

        proposal::create_proposal(
            &proposer,
            dao_addr,
            string::utf8(b"Second Proposal"),
            string::utf8(b"Second one"),
            3600,
            3600,
            30
        );
        assert!(proposal::get_proposals_count(dao_addr) == 2, EASSERTION_FAILED + 13);

        test_utils::destroy_caps(aptos_framework);
    }
}