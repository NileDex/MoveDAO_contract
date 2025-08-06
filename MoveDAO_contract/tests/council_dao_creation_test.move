#[test_only]
module dao_addr::council_dao_creation_test {
    use std::vector;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use dao_addr::dao_core;

    #[test(aptos_framework = @0x1, council_creator = @dao_addr, council_member1 = @0x3, council_member2 = @0x4, target_dao = @0x5)]
    public entry fun test_council_dao_creation_lifecycle(
        aptos_framework: &signer,
        council_creator: &signer,
        council_member1: &signer,
        council_member2: &signer,
        target_dao: &signer
    ) {
        // Setup test environment
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos_framework);

        // Create test accounts
        account::create_account_for_test(@dao_addr);
        account::create_account_for_test(@0x3);
        account::create_account_for_test(@0x4);
        account::create_account_for_test(@0x5);

        // Create initial council DAO
        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, @0x3);
        vector::push_back(&mut initial_council, @0x4);

        dao_core::create_dao(
            council_creator,
            string::utf8(b"Council DAO"),
            string::utf8(b"A DAO managed by a council"),
            vector::empty<u8>(), // logo
            vector::empty<u8>(), // background
            initial_council,
            100, // min_stake_to_join
            3600, // min_voting_period (1 hour)
            259200 // max_voting_period (3 days)
        );

        // Initialize council DAO creation registry
        dao_core::init_council_dao_creation(council_creator, 86400); // 1 day voting period

        // Council member proposes new DAO creation
        let target_initial_council = vector::empty<address>();
        vector::push_back(&mut target_initial_council, @0x5);

        dao_core::propose_dao_creation(
            council_member1,
            @dao_addr,
            @0x5,
            string::utf8(b"New DAO"),
            string::utf8(b"A new DAO created by council"),
            vector::empty<u8>(), // logo
            vector::empty<u8>(), // background
            target_initial_council,
            200, // min_stake_to_join
            7200, // min_voting_period (2 hours)
            432000 // max_voting_period (5 days)
        );

        // Verify proposal was created
        assert!(dao_core::get_dao_creation_proposal_count(@dao_addr) == 1, 100);
        
        let (id, proposer, target_addr, name, _description, _created_at, _deadline, yes_votes, no_votes, executed, approved) = 
            dao_core::get_dao_creation_proposal(@dao_addr, 0);
        
        assert!(id == 0, 101);
        assert!(proposer == @0x3, 102);
        assert!(target_addr == @0x5, 103);
        assert!(name == string::utf8(b"New DAO"), 104);
        assert!(yes_votes == 0, 105);
        assert!(no_votes == 0, 106);
        assert!(!executed, 107);
        assert!(!approved, 108);

        // Council members vote on the proposal
        dao_core::vote_on_dao_creation(council_member1, @dao_addr, 0, true); // yes vote
        dao_core::vote_on_dao_creation(council_member2, @dao_addr, 0, true); // yes vote

        // Verify votes were recorded
        assert!(dao_core::has_voted_on_dao_creation(@dao_addr, 0, @0x3), 109);
        assert!(dao_core::has_voted_on_dao_creation(@dao_addr, 0, @0x4), 110);

        // Fast forward time to end voting period
        timestamp::update_global_time_for_test_secs(86401);

        // Execute the proposal
        dao_core::execute_dao_creation(council_member1, @dao_addr, 0);

        // Verify proposal was executed and approved
        let (_, _, _, _, _, _, _, yes_votes_after, _, executed_after, approved_after) = 
            dao_core::get_dao_creation_proposal(@dao_addr, 0);
        
        assert!(yes_votes_after == 2, 111);
        assert!(executed_after, 112);
        assert!(approved_after, 113);

        // Target account finalizes DAO creation
        dao_core::finalize_council_created_dao(target_dao, @dao_addr, 0);

        // Verify new DAO was created
        let (dao_name, dao_desc, _, _, _) = dao_core::get_dao_info(@0x5);
        assert!(dao_name == string::utf8(b"New DAO"), 114);
        assert!(dao_desc == string::utf8(b"A new DAO created by council"), 115);

        // Cleanup
        aptos_framework::coin::destroy_mint_cap(mint_cap);
        aptos_framework::coin::destroy_burn_cap(burn_cap);
    }

    #[test(aptos_framework = @0x1, council_creator = @dao_addr, council_member1 = @0x3, _council_member2 = @0x4)]
    #[expected_failure(abort_code = 602, location = dao_addr::dao_core)]
    public entry fun test_vote_on_nonexistent_proposal(
        aptos_framework: &signer,
        council_creator: &signer,
        council_member1: &signer,
        _council_member2: &signer
    ) {
        // Setup test environment
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos_framework);

        account::create_account_for_test(@dao_addr);
        account::create_account_for_test(@0x3);
        account::create_account_for_test(@0x4);

        // Create initial council DAO
        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, @0x3);
        vector::push_back(&mut initial_council, @0x4);

        dao_core::create_dao(
            council_creator,
            string::utf8(b"Council DAO"),
            string::utf8(b"A DAO managed by a council"),
            vector::empty<u8>(),
            vector::empty<u8>(),
            initial_council,
            100,
            3600,
            259200
        );

        dao_core::init_council_dao_creation(council_creator, 86400);

        // Try to vote on non-existent proposal - should fail
        dao_core::vote_on_dao_creation(council_member1, @dao_addr, 0, true);

        aptos_framework::coin::destroy_mint_cap(mint_cap);
        aptos_framework::coin::destroy_burn_cap(burn_cap);
    }

    #[test(aptos_framework = @0x1, council_creator = @dao_addr, non_member = @0x3)]
    #[expected_failure(abort_code = 601, location = dao_addr::dao_core)]
    public entry fun test_non_member_cannot_propose(
        aptos_framework: &signer,
        council_creator: &signer,
        non_member: &signer
    ) {
        // Setup test environment
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos_framework);

        account::create_account_for_test(@dao_addr);
        account::create_account_for_test(@0x3);

        // Create council DAO with council_creator as the only member
        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, @dao_addr);
        
        dao_core::create_dao(
            council_creator,
            string::utf8(b"Council DAO"),
            string::utf8(b"A DAO managed by a council"),
            vector::empty<u8>(),
            vector::empty<u8>(),
            initial_council,
            100,
            3600,
            259200
        );

        dao_core::init_council_dao_creation(council_creator, 86400);

        let target_initial_council = vector::empty<address>();
        vector::push_back(&mut target_initial_council, @0x3);

        // Non-member tries to propose - should fail
        dao_core::propose_dao_creation(
            non_member,
            @dao_addr,
            @0x3,
            string::utf8(b"New DAO"),
            string::utf8(b"A new DAO created by council"),
            vector::empty<u8>(),
            vector::empty<u8>(),
            target_initial_council,
            200,
            7200,
            432000
        );

        aptos_framework::coin::destroy_mint_cap(mint_cap);
        aptos_framework::coin::destroy_burn_cap(burn_cap);
    }
}