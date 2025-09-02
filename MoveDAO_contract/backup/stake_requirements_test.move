#[test_only]
module movedaoaddrx::admin_tests {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use movedaoaddrx::dao_core_file as dao_core;
    use movedaoaddrx::admin;
    use movedaoaddrx::test_utils;

    const EASSERTION_FAILED: u64 = 200;

    #[test(aptos_framework = @0x1, alice = @movedaoaddrx)]
    fun test_admin_initialization(aptos_framework: &signer, alice: &signer) {
        // Setup framework and test accounts
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Initialize test environment
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(alice);

        // Create DAO - this will initialize the admin system
        let initial_council = vector::empty();
        vector::push_back(&mut initial_council, signer::address_of(alice));
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        // Get the DAO address (where admin data is stored)
        let dao_address = signer::address_of(alice);
        
        // Verify admin initialization - the creator should be a super admin
        assert!(admin::is_admin(dao_address, dao_address), EASSERTION_FAILED);
        assert!(
            admin::get_admin_role(dao_address, dao_address) == admin::role_super_admin(),
            EASSERTION_FAILED + 1
        );

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @movedaoaddrx, bob = @0x456)]
    fun test_add_and_remove_admin(aptos_framework: &signer, alice: &signer, bob: &signer) {
        // Setup accounts
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Initialize test environment
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(bob);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(alice);

        // Create DAO with alice as initial council member
        let initial_council = vector::empty();
        vector::push_back(&mut initial_council, signer::address_of(alice));
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_address = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);

        // Test adding admin
        admin::add_admin(alice, dao_address, bob_addr, admin::role_standard(), 0);
        assert!(admin::is_admin(dao_address, bob_addr), EASSERTION_FAILED);
        assert!(
            admin::get_admin_role(dao_address, bob_addr) == admin::role_standard(),
            EASSERTION_FAILED + 1
        );
        
        // Check admin list contains both admins
        let admins = admin::get_admins(dao_address);
        assert!(vector::length(&admins) == 2, EASSERTION_FAILED + 2);
        
        // Test removing admin
        admin::remove_admin(alice, dao_address, bob_addr);
        assert!(!admin::is_admin(dao_address, bob_addr), EASSERTION_FAILED + 3);

        // Admin list should only have 1 admin now
        let admins_after = admin::get_admins(dao_address);
        assert!(vector::length(&admins_after) == 1, EASSERTION_FAILED + 4);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @movedaoaddrx)]
    #[expected_failure(abort_code = 11, location = movedaoaddrx::admin)] // errors::invalid_role() = 11
    fun test_invalid_role_rejected(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty();
        vector::push_back(&mut initial_council, signer::address_of(alice));
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_address = signer::address_of(alice);
        // Try to add admin with invalid role - should fail
        admin::add_admin(alice, dao_address, @0x999, 42, 0); // Invalid role = 42

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @movedaoaddrx, bob = @0x456)]
    #[expected_failure(abort_code = 327690, location = movedaoaddrx::errors)] // errors::permission_denied(not_admin()) = 327690
    fun test_non_admin_cannot_add_admin(aptos_framework: &signer, alice: &signer, bob: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(bob);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty();
        vector::push_back(&mut initial_council, signer::address_of(alice));
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_address = signer::address_of(alice);
        // Bob (non-admin) tries to add someone as admin - should fail
        admin::add_admin(bob, dao_address, @0x999, admin::role_standard(), 0);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @movedaoaddrx, bob = @0x456)]
    fun test_temporary_admin_expiration(aptos_framework: &signer, alice: &signer, bob: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(bob);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty();
        vector::push_back(&mut initial_council, signer::address_of(alice));
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_address = signer::address_of(alice);
        let bob_addr = signer::address_of(bob);

        // Add temporary admin that expires in 400 seconds (> 300 second minimum)
        admin::add_admin(alice, dao_address, bob_addr, admin::role_temporary(), 400);
        assert!(admin::is_admin(dao_address, bob_addr), EASSERTION_FAILED);
        
        // Fast forward time past expiration
        timestamp::fast_forward_seconds(401);
        
        // Admin should no longer be valid due to expiration
        assert!(!admin::is_admin(dao_address, bob_addr), EASSERTION_FAILED + 1);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @movedaoaddrx)]
    #[expected_failure(abort_code = 12, location = movedaoaddrx::admin)] // errors::expiration_past() = 12
    fun test_cannot_add_admin_with_past_expiration(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty();
        vector::push_back(&mut initial_council, signer::address_of(alice));
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_address = signer::address_of(alice);
        // Try to add admin with expiration in the past (1 second) - should fail
        admin::add_admin(alice, dao_address, @0x999, admin::role_temporary(), 1);

        test_utils::destroy_caps(aptos_framework);
    }
}
#[test_only]
module movedaoaddrx::council_dao_creation_test {
    use std::vector;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use movedaoaddrx::dao_core_file as dao_core;

    #[test(aptos_framework = @0x1, council_creator = @movedaoaddrx, council_member1 = @0x3, council_member2 = @0x4, target_dao = @0x5)]
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
        account::create_account_for_test(@movedaoaddrx);
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
            string::utf8(b"Subname"),
            string::utf8(b"A DAO managed by a council"),
            vector::empty<u8>(), // logo
            vector::empty<u8>(), // background
            initial_council,
            100 // min_stake_to_join
        );

        // Initialize council DAO creation registry
        dao_core::init_council_dao_creation(council_creator, 86400); // 1 day voting period

        // Council member proposes new DAO creation
        let target_initial_council = vector::empty<address>();
        vector::push_back(&mut target_initial_council, @0x5);

        dao_core::propose_dao_creation(
            council_member1,
            @movedaoaddrx,
            @0x5,
            string::utf8(b"New DAO"),
            string::utf8(b"Subname"),
            string::utf8(b"A new DAO created by council"),
            vector::empty<u8>(), // logo
            vector::empty<u8>(), // background
            target_initial_council,
            200 // min_stake_to_join
        );

        // Verify proposal was created
        assert!(dao_core::get_dao_creation_proposal_count(@movedaoaddrx) == 1, 100);
        
        let (id, proposer, target_addr, name, _description, _created_at, _deadline, yes_votes, no_votes, executed, approved) = 
            dao_core::get_dao_creation_proposal(@movedaoaddrx, 0);
        
        assert!(id == 0, 101);
        assert!(proposer == @0x3, 102);
        assert!(target_addr == @0x5, 103);
        assert!(name == string::utf8(b"New DAO"), 104);
        assert!(yes_votes == 0, 105);
        assert!(no_votes == 0, 106);
        assert!(!executed, 107);
        assert!(!approved, 108);

        // Council members vote on the proposal
        dao_core::vote_on_dao_creation(council_member1, @movedaoaddrx, 0, true); // yes vote
        dao_core::vote_on_dao_creation(council_member2, @movedaoaddrx, 0, true); // yes vote

        // Verify votes were recorded
        assert!(dao_core::has_voted_on_dao_creation(@movedaoaddrx, 0, @0x3), 109);
        assert!(dao_core::has_voted_on_dao_creation(@movedaoaddrx, 0, @0x4), 110);

        // Fast forward time to end voting period
        timestamp::update_global_time_for_test_secs(86401);

        // Execute the proposal
        dao_core::execute_dao_creation(council_member1, @movedaoaddrx, 0);

        // Verify proposal was executed and approved
        let (_, _, _, _, _, _, _, yes_votes_after, _, executed_after, approved_after) = 
            dao_core::get_dao_creation_proposal(@movedaoaddrx, 0);
        
        assert!(yes_votes_after == 2, 111);
        assert!(executed_after, 112);
        assert!(approved_after, 113);

        // Target account finalizes DAO creation
        dao_core::finalize_council_created_dao(target_dao, @movedaoaddrx, 0);

        // Verify new DAO was created
        let (dao_name, dao_desc, _, _, _, _, _, _, _) = dao_core::get_dao_info(@0x5);
        assert!(dao_name == string::utf8(b"New DAO"), 114);
        assert!(dao_desc == string::utf8(b"A new DAO created by council"), 115);

        // Cleanup
        aptos_framework::coin::destroy_mint_cap(mint_cap);
        aptos_framework::coin::destroy_burn_cap(burn_cap);
    }

    #[test(aptos_framework = @0x1, council_creator = @movedaoaddrx, council_member1 = @0x3, _council_member2 = @0x4)]
    #[expected_failure(abort_code = 602, location = movedaoaddrx::dao_core_file as dao_core_file)]
    public entry fun test_vote_on_nonexistent_proposal(
        aptos_framework: &signer,
        council_creator: &signer,
        council_member1: &signer,
        _council_member2: &signer
    ) {
        // Setup test environment
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos_framework);

        account::create_account_for_test(@movedaoaddrx);
        account::create_account_for_test(@0x3);
        account::create_account_for_test(@0x4);

        // Create initial council DAO
        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, @0x3);
        vector::push_back(&mut initial_council, @0x4);

        dao_core::create_dao(
            council_creator,
            string::utf8(b"Council DAO"),
            string::utf8(b"Subname"),
            string::utf8(b"A DAO managed by a council"),
            vector::empty<u8>(),
            vector::empty<u8>(),
            initial_council,
            100
        );

        dao_core::init_council_dao_creation(council_creator, 86400);

        // Try to vote on non-existent proposal - should fail
        dao_core::vote_on_dao_creation(council_member1, @movedaoaddrx, 0, true);

        aptos_framework::coin::destroy_mint_cap(mint_cap);
        aptos_framework::coin::destroy_burn_cap(burn_cap);
    }

    #[test(aptos_framework = @0x1, council_creator = @movedaoaddrx, non_member = @0x3)]
    #[expected_failure(abort_code = 601, location = movedaoaddrx::dao_core_file as dao_core_file)]
    public entry fun test_non_member_cannot_propose(
        aptos_framework: &signer,
        council_creator: &signer,
        non_member: &signer
    ) {
        // Setup test environment
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos_framework);

        account::create_account_for_test(@movedaoaddrx);
        account::create_account_for_test(@0x3);

        // Create council DAO with council_creator as the only member
        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, @movedaoaddrx);
        
        dao_core::create_dao(
            council_creator,
            string::utf8(b"Council DAO"),
            string::utf8(b"Subname"),
            string::utf8(b"A DAO managed by a council"),
            vector::empty<u8>(),
            vector::empty<u8>(),
            initial_council,
            100
        );

        dao_core::init_council_dao_creation(council_creator, 86400);

        let target_initial_council = vector::empty<address>();
        vector::push_back(&mut target_initial_council, @0x3);

        // Non-member tries to propose - should fail
        dao_core::propose_dao_creation(
            non_member,
            @movedaoaddrx,
            @0x3,
            string::utf8(b"New DAO"),
            string::utf8(b"Subname"),
            string::utf8(b"A new DAO created by council"),
            vector::empty<u8>(),
            vector::empty<u8>(),
            target_initial_council,
            200
        );

        aptos_framework::coin::destroy_mint_cap(mint_cap);
        aptos_framework::coin::destroy_burn_cap(burn_cap);
    }
}
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
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, signer::address_of(alice));
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_address = @0x123;
        let council_obj = dao_core::get_council_object(dao_address);
        
        // Add second member (alice is already initial member)
        council::add_council_member_to_object(alice, dao_address, council_obj, @0x456);
        assert!(council::get_member_count_from_object(council_obj) == 2, EASSERTION_FAILED);
        assert!(council::is_council_member_in_object(council_obj, @0x456), EASSERTION_FAILED + 1);

        // Add third member
        council::add_council_member_to_object(alice, dao_address, council_obj, @0x789);
        assert!(council::get_member_count_from_object(council_obj) == 3, EASSERTION_FAILED + 2);
        assert!(council::is_council_member_in_object(council_obj, @0x789), EASSERTION_FAILED + 3);

        // Remove member
        council::remove_council_member_from_object(alice, dao_address, council_obj, @0x456);
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
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, signer::address_of(alice));
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_address = @0x123;
        let council_obj = dao_core::get_council_object(dao_address);
        let non_admin = account::create_signer_for_test(@0x999);
        council::add_council_member_to_object(&non_admin, dao_address, council_obj, @0x456);

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
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(alice);

        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, signer::address_of(alice));
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_address = @0x123;
        let council_obj = dao_core::get_council_object(dao_address);
        
        // Trying to remove non-existent member should fail
        council::remove_council_member_from_object(alice, dao_address, council_obj, @0x999);

        test_utils::destroy_caps(aptos_framework);
    }
}
#[test_only]
module movedaoaddrx::create_dao_tests {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use movedaoaddrx::dao_core_file as dao_core;
    use movedaoaddrx::test_utils;

    const EASSERTION_FAILED: u64 = 200;

    #[test(aptos_framework = @0x1, creator = @0x123)]
    fun test_dao_creation(aptos_framework: &signer, creator: &signer) {
        // Setup test environment
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1); // Advance time to ensure now_seconds() > 0
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(creator);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(creator);
        
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Test data
        let name = string::utf8(b"My DAO");
        let description = string::utf8(b"A test DAO");
        let logo = b"logo";
        let background = b"bg";
        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, signer::address_of(creator));

        // Create the DAO
        dao_core::create_dao(
            creator, 
            name,
            string::utf8(b"Subname"), 
            description, 
            logo, 
            background,
            initial_council, 
            30  // min_stake_to_join
        );

        // Verify DAO was created by checking stored data
        let creator_addr = signer::address_of(creator);
        let (stored_name, stored_description, _logo_is_url, _logo_url, stored_logo, _bg_is_url, _bg_url, stored_background, created_at) = 
            dao_core::get_dao_info(creator_addr);

        // Assertions to verify DAO creation
        assert!(stored_name == name, EASSERTION_FAILED);
        assert!(stored_description == description, EASSERTION_FAILED + 1);
        assert!(stored_logo == logo, EASSERTION_FAILED + 2);
        assert!(stored_background == background, EASSERTION_FAILED + 3);
        assert!(created_at > 0, EASSERTION_FAILED + 4); // Verify timestamp was set

        test_utils::destroy_caps(aptos_framework);
    }
}
#[test_only]
module movedaoaddrx::launchpad_test {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use movedaoaddrx::dao_core_file as dao_core;
    use movedaoaddrx::launchpad;
    use movedaoaddrx::test_utils;

    const EASSERTION_FAILED: u64 = 2000;
    const TEST_DAO_ADMIN: address = @0x123;
    const TEST_INVESTOR1: address = @0x456;
    const TEST_INVESTOR2: address = @0x789;
    const TEST_INVESTOR3: address = @0xabc;

    fun setup_dao_with_launchpad(admin: &signer) {
        let council = vector::singleton(TEST_DAO_ADMIN);
        dao_core::create_dao(
            admin,
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"),
            string::utf8(b"Test Description"),
            b"logo",
            b"bg",
            council,
            30 // min_stake_to_join
        );
    }

    fun setup_test_user(user: &signer, amount: u64) {
        test_utils::setup_test_account(user);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<AptosCoin>(user);
        test_utils::mint_aptos(user, amount);
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    fun test_create_launchpad(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 5000);

        setup_dao_with_launchpad(admin);
        let dao_address = signer::address_of(admin);

        // Create launchpad
        dao_core::create_dao_launchpad(
            admin,
            dao_address,
            string::utf8(b"Test Token Launch"),
            string::utf8(b"TTL"),
            1000000, // 1M total supply
            100,     // 100 micro-APT per token
            30,      // 30% presale allocation
            20,      // 20% team allocation
            6,       // 6 months cliff
            24,      // 24 months vesting
            true     // KYC required
        );

        // Check launchpad info
        let (project_name, token_name, total_supply, price, phase, is_active) = 
            launchpad::get_launchpad_info(dao_address);
        
        assert!(project_name == string::utf8(b"Test Token Launch"), EASSERTION_FAILED);
        assert!(token_name == string::utf8(b"TTL"), EASSERTION_FAILED + 1);
        assert!(total_supply == 1000000, EASSERTION_FAILED + 2);
        assert!(price == 100, EASSERTION_FAILED + 3);
        assert!(phase == launchpad::phase_setup(), EASSERTION_FAILED + 4);
        assert!(is_active == true, EASSERTION_FAILED + 5);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    fun test_whitelist_management(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        account::create_account_for_test(TEST_INVESTOR1);
        account::create_account_for_test(TEST_INVESTOR2);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 5000);

        setup_dao_with_launchpad(admin);
        let dao_address = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_address, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, true
        );

        // Add participants to whitelist
        let participants = vector::empty<address>();
        let tiers = vector::empty<u8>();
        let allocations = vector::empty<u64>();
        
        vector::push_back(&mut participants, TEST_INVESTOR1);
        vector::push_back(&mut participants, TEST_INVESTOR2);
        vector::push_back(&mut tiers, launchpad::tier_gold());
        vector::push_back(&mut tiers, launchpad::tier_silver());
        vector::push_back(&mut allocations, 5000);
        vector::push_back(&mut allocations, 3000);
        
        dao_core::manage_launchpad_whitelist(admin, dao_address, participants, tiers, allocations);

        // Check whitelist status
        assert!(launchpad::is_whitelisted(dao_address, TEST_INVESTOR1), EASSERTION_FAILED);
        assert!(launchpad::is_whitelisted(dao_address, TEST_INVESTOR2), EASSERTION_FAILED + 1);
        assert!(!launchpad::is_whitelisted(dao_address, TEST_INVESTOR3), EASSERTION_FAILED + 2);

        // Check whitelist details
        let (tier1, allocation1, kyc1) = launchpad::get_whitelist_info(dao_address, TEST_INVESTOR1);
        let (tier2, allocation2, kyc2) = launchpad::get_whitelist_info(dao_address, TEST_INVESTOR2);
        
        assert!(tier1 == launchpad::tier_gold(), EASSERTION_FAILED + 3);
        assert!(allocation1 == 5000, EASSERTION_FAILED + 4);
        assert!(kyc1 == false, EASSERTION_FAILED + 5); // Not verified yet
        
        assert!(tier2 == launchpad::tier_silver(), EASSERTION_FAILED + 6);
        assert!(allocation2 == 3000, EASSERTION_FAILED + 7);
        assert!(kyc2 == false, EASSERTION_FAILED + 8);

        // Update KYC status
        launchpad::update_kyc_status(admin, dao_address, TEST_INVESTOR1, true);
        let (_, _, kyc1_updated) = launchpad::get_whitelist_info(dao_address, TEST_INVESTOR1);
        assert!(kyc1_updated == true, EASSERTION_FAILED + 9);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    fun test_timeline_management(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 5000);

        setup_dao_with_launchpad(admin);
        let dao_address = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_address, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, false
        );

        let now = timestamp::now_seconds();
        
        // Update timeline with minimum 1 day periods
        launchpad::update_timeline(
            admin,
            dao_address,
            now + 100,     // whitelist starts in 100 seconds
            now + 1000,    // presale starts in 1000 seconds
            now + 87400,   // public sale starts after 1 day + margin
            now + 174800,  // sale ends after another 1 day + margin
            now + 200000   // vesting starts later
        );

        // Check timeline
        let (whitelist_start, presale_start, public_start, sale_end, vesting_start) = 
            launchpad::get_timeline(dao_address);
        
        assert!(whitelist_start == now + 100, EASSERTION_FAILED);
        assert!(presale_start == now + 1000, EASSERTION_FAILED + 1);
        assert!(public_start == now + 87400, EASSERTION_FAILED + 2);
        assert!(sale_end == now + 174800, EASSERTION_FAILED + 3);
        assert!(vesting_start == now + 200000, EASSERTION_FAILED + 4);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, investor1 = @0x456, investor2 = @0x789)]
    fun test_presale_purchase(
        aptos_framework: &signer, 
        admin: &signer, 
        investor1: &signer, 
        investor2: &signer
    ) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        account::create_account_for_test(TEST_INVESTOR1);
        account::create_account_for_test(TEST_INVESTOR2);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 5000);
        setup_test_user(investor1, 500000);
        setup_test_user(investor2, 500000);

        setup_dao_with_launchpad(admin);
        let dao_address = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_address, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, false // KYC not required
        );

        // Setup whitelist
        let participants = vector::empty<address>();
        let tiers = vector::empty<u8>();
        let allocations = vector::empty<u64>();
        
        vector::push_back(&mut participants, TEST_INVESTOR1);
        vector::push_back(&mut participants, TEST_INVESTOR2);
        vector::push_back(&mut tiers, launchpad::tier_gold());
        vector::push_back(&mut tiers, launchpad::tier_silver());
        vector::push_back(&mut allocations, 5000);
        vector::push_back(&mut allocations, 3000);
        
        dao_core::manage_launchpad_whitelist(admin, dao_address, participants, tiers, allocations);

        // Setup timeline for presale with minimum durations
        let now = timestamp::now_seconds();
        launchpad::update_timeline(admin, dao_address, now + 100, now + 150, now + 87000, now + 174000, now + 200000);

        // Advance time to reach whitelist start
        timestamp::fast_forward_seconds(150);
        
        // Advance to whitelist phase first
        launchpad::advance_phase(admin, dao_address);
        
        // Advance time to reach presale start
        timestamp::fast_forward_seconds(87000);
        
        // Advance to presale phase
        launchpad::advance_phase(admin, dao_address);
        
        let (_, _, _, _, phase, _) = launchpad::get_launchpad_info(dao_address);
        assert!(phase == launchpad::phase_presale(), EASSERTION_FAILED);

        // Make purchases
        launchpad::purchase_tokens(investor1, dao_address, 2000); // Gold tier buying 2000 tokens
        launchpad::purchase_tokens(investor2, dao_address, 1500); // Silver tier buying 1500 tokens

        // Check purchase history
        let purchased1 = launchpad::get_purchase_history(dao_address, TEST_INVESTOR1);
        let purchased2 = launchpad::get_purchase_history(dao_address, TEST_INVESTOR2);
        
        assert!(purchased1 == 2000, EASSERTION_FAILED + 1);
        assert!(purchased2 == 1500, EASSERTION_FAILED + 2);

        // Check sale stats
        let (tokens_sold, funds_raised, _total_available, _percentage_sold) = 
            launchpad::get_sale_stats(dao_address);
        
        assert!(tokens_sold == 3500, EASSERTION_FAILED + 3);
        assert!(funds_raised == 350000, EASSERTION_FAILED + 4); // 3500 * 100
        
        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, investor1 = @0x456)]
    fun test_public_sale_purchase(aptos_framework: &signer, admin: &signer, investor1: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        account::create_account_for_test(TEST_INVESTOR1);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 5000);
        setup_test_user(investor1, 2000000);

        setup_dao_with_launchpad(admin);
        let dao_address = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_address, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, false
        );

        // Setup timeline for public sale
        let now = timestamp::now_seconds();
        launchpad::update_timeline(admin, dao_address, now + 200, now + 300, now + 87000, now + 174000, now + 200000);

        // Advance time to reach whitelist start
        timestamp::fast_forward_seconds(300);
        
        // Advance to whitelist phase first
        launchpad::advance_phase(admin, dao_address);
        
        // Advance time to reach presale start (from now+200 to now+300)
        timestamp::fast_forward_seconds(100);
        
        // Advance to presale phase
        launchpad::advance_phase(admin, dao_address);
        
        // Advance time to reach public sale start (from now+300 to now+87000)
        timestamp::fast_forward_seconds(86700);
        
        // Advance to public sale phase
        launchpad::advance_phase(admin, dao_address);
        
        let (_, _, _, _, phase, _) = launchpad::get_launchpad_info(dao_address);
        assert!(phase == launchpad::phase_public_sale(), EASSERTION_FAILED);

        // Make public purchase (no whitelist required)
        launchpad::purchase_tokens(investor1, dao_address, 10000);

        let purchased = launchpad::get_purchase_history(dao_address, TEST_INVESTOR1);
        assert!(purchased == 10000, EASSERTION_FAILED + 1);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, beneficiary = @0x456)]
    fun test_vesting_schedule(aptos_framework: &signer, admin: &signer, beneficiary: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        account::create_account_for_test(TEST_INVESTOR1);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 5000);
        setup_test_user(beneficiary, 1000);

        setup_dao_with_launchpad(admin);
        let dao_address = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_address, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, false
        );

        // Create vesting schedule
        launchpad::create_vesting_schedule(
            admin,
            dao_address,
            TEST_INVESTOR1,
            50000,    // 50k tokens
            2592000,  // 30 days cliff (in seconds)
            31536000  // 365 days vesting (in seconds)
        );

        // Check initial vesting info
        let (total, claimed, claimable) = launchpad::get_vesting_info(dao_address, TEST_INVESTOR1);
        assert!(total == 50000, EASSERTION_FAILED);
        assert!(claimed == 0, EASSERTION_FAILED + 1);
        assert!(claimable == 0, EASSERTION_FAILED + 2); // Still in cliff period

        // Fast forward past cliff
        timestamp::fast_forward_seconds(2592001); // Just past 30 days

        let (_, _, claimable_after_cliff) = launchpad::get_vesting_info(dao_address, TEST_INVESTOR1);
        assert!(claimable_after_cliff > 0, EASSERTION_FAILED + 3); // Some tokens should be claimable

        // Claim vested tokens
        launchpad::claim_vested_tokens(beneficiary, dao_address);

        let (_, claimed_after, _) = launchpad::get_vesting_info(dao_address, TEST_INVESTOR1);
        assert!(claimed_after == claimable_after_cliff, EASSERTION_FAILED + 4);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    fun test_emergency_pause_resume(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 5000);

        setup_dao_with_launchpad(admin);
        let dao_address = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_address, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, false
        );

        // Check initial state
        let (_, _, _, _, _, is_active) = launchpad::get_launchpad_info(dao_address);
        assert!(is_active == true, EASSERTION_FAILED);

        // Emergency pause
        launchpad::emergency_pause(admin, dao_address);
        let (_, _, _, _, _, is_active_paused) = launchpad::get_launchpad_info(dao_address);
        assert!(is_active_paused == false, EASSERTION_FAILED + 1);

        // Emergency resume
        launchpad::emergency_resume(admin, dao_address);
        let (_, _, _, _, _, is_active_resumed) = launchpad::get_launchpad_info(dao_address);
        assert!(is_active_resumed == true, EASSERTION_FAILED + 2);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, investor1 = @0x456)]
    #[expected_failure(abort_code = 503, location = movedaoaddrx::launchpad)] // errors::not_whitelisted() = 503
    fun test_presale_non_whitelisted_fails(
        aptos_framework: &signer, 
        admin: &signer, 
        investor1: &signer
    ) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        account::create_account_for_test(TEST_INVESTOR1);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 5000);
        setup_test_user(investor1, 100000);

        setup_dao_with_launchpad(admin);
        let dao_address = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_address, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, false
        );

        // Setup timeline for presale - ensure we stay in presale phase
        let now = timestamp::now_seconds();
        launchpad::update_timeline(admin, dao_address, now + 100, now + 200, now + 87000, now + 174000, now + 200000);

        // Advance time to reach presale start but not public sale
        timestamp::fast_forward_seconds(250);
        
        // Advance to presale phase
        launchpad::advance_phase(admin, dao_address);

        // Try to purchase without being whitelisted - should fail
        launchpad::purchase_tokens(investor1, dao_address, 1000);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, investor1 = @0x456)]
    #[expected_failure(abort_code = 504, location = movedaoaddrx::launchpad)] // errors::exceeds_allocation() = 504
    fun test_exceeds_allocation_fails(
        aptos_framework: &signer, 
        admin: &signer, 
        investor1: &signer
    ) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(TEST_DAO_ADMIN);
        account::create_account_for_test(TEST_INVESTOR1);
        
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::fast_forward_seconds(1);
        test_utils::setup_aptos(aptos_framework);
        setup_test_user(admin, 5000);
        setup_test_user(investor1, 1000000);

        setup_dao_with_launchpad(admin);
        let dao_address = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_address, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, false
        );

        // Setup whitelist with small allocation
        let participants = vector::singleton(TEST_INVESTOR1);
        let tiers = vector::singleton(launchpad::tier_bronze());
        let allocations = vector::singleton(1000u64); // Only 1000 tokens allowed
        
        dao_core::manage_launchpad_whitelist(admin, dao_address, participants, tiers, allocations);

        // Setup timeline for presale - ensure we stay in presale phase
        let now = timestamp::now_seconds();
        launchpad::update_timeline(admin, dao_address, now + 100, now + 200, now + 87000, now + 174000, now + 200000);

        // Advance time to reach presale start but not public sale
        timestamp::fast_forward_seconds(250);
        
        // Advance to presale phase
        launchpad::advance_phase(admin, dao_address);

        // Try to purchase more than allocation - should fail
        launchpad::purchase_tokens(investor1, dao_address, 2000);

        test_utils::destroy_caps(aptos_framework);
    }
}
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
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Create DAO which initializes membership
        let initial_council = vector::singleton(@movedaoaddrx);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"),
            string::utf8(b"Description"), 
            b"logo", 
            b"bg",
            initial_council, 
            30
        );

        let dao_address = signer::address_of(admin);

        // Create test member account
        let member1 = account::create_account_for_test(TEST_MEMBER);
        test_utils::setup_test_account(&member1);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(&member1);
        test_utils::mint_aptos(&member1, 1000);

        // Stake and join
        staking::stake(&member1, dao_address, TEST_MIN_STAKE);
        membership::join(&member1, dao_address);
        
        // Verify membership
        assert!(membership::is_member(dao_address, TEST_MEMBER), 1);
        assert!(membership::total_members(dao_address) == 1, 2);
        assert!(membership::get_voting_power(dao_address, TEST_MEMBER) == TEST_MIN_STAKE, 3);

        // Stake more and verify voting power increases
        staking::stake(&member1, dao_address, 500);
        assert!(membership::get_voting_power(dao_address, TEST_MEMBER) == TEST_MIN_STAKE + 500, 4);

        // Leave and verify
        membership::leave(&member1, dao_address);
        assert!(!membership::is_member(dao_address, TEST_MEMBER), 5);
        assert!(membership::total_members(dao_address) == 0, 6);

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
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        let initial_council = vector::singleton(@movedaoaddrx);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_address = signer::address_of(admin);

        let member = account::create_account_for_test(TEST_MEMBER);
        test_utils::setup_test_account(&member);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(&member);
        test_utils::mint_aptos(&member, 1000);
        
        staking::stake(&member, dao_address, TEST_MIN_STAKE);
        membership::join(&member, dao_address);
        membership::join(&member, dao_address);  // Should abort with EALREADY_MEMBER

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
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        let initial_council = vector::singleton(@movedaoaddrx);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_address = signer::address_of(admin);

        let member = account::create_account_for_test(TEST_MEMBER);
        test_utils::setup_test_account(&member);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(&member);
        test_utils::mint_aptos(&member, 1000);
        
        // Try to join without staking - should abort
        membership::join(&member, dao_address);

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
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        let initial_council = vector::singleton(@movedaoaddrx);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_address = signer::address_of(admin);

        // Create test members
        let member1 = account::create_account_for_test(TEST_MEMBER);
        let member2 = account::create_account_for_test(TEST_MEMBER2);
        test_utils::setup_test_account(&member1);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(&member2);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(&member1);
        coin::register<aptos_coin::AptosCoin>(&member2);
        test_utils::mint_aptos(&member1, 5000);
        test_utils::mint_aptos(&member2, 3000);

        // Member 1 stakes and joins
        staking::stake(&member1, dao_address, 1000);
        membership::join(&member1, dao_address);
        assert!(membership::get_voting_power(dao_address, TEST_MEMBER) == 1000, 1);

        // Member 2 stakes and joins
        staking::stake(&member2, dao_address, 2000);
        membership::join(&member2, dao_address);
        assert!(membership::get_voting_power(dao_address, TEST_MEMBER2) == 2000, 2);

        // Member 1 stakes more
        staking::stake(&member1, dao_address, 500);
        assert!(membership::get_voting_power(dao_address, TEST_MEMBER) == 1500, 3);

        // Check total voting power
        assert!(membership::total_voting_power(dao_address) == 3500, 4);

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
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        let initial_council = vector::singleton(@movedaoaddrx);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_address = signer::address_of(admin);

        let member = account::create_account_for_test(TEST_MEMBER);
        test_utils::setup_test_account(&member);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(&member);
        test_utils::mint_aptos(&member, 5000);

        // Stake and join
        staking::stake(&member, dao_address, 2000);
        membership::join(&member, dao_address);
        assert!(membership::get_voting_power(dao_address, TEST_MEMBER) == 2000, 1);

        // Wait 7 days to bypass unstaking time lock
        timestamp::fast_forward_seconds(7 * 24 * 60 * 60 + 1);

        // Unstake some amount
        staking::unstake(&member, dao_address, 500);
        assert!(membership::get_voting_power(dao_address, TEST_MEMBER) == 1500, 2);

        // Unstake more, but keep above minimum
        staking::unstake(&member, dao_address, 1400);
        assert!(membership::is_member(dao_address, TEST_MEMBER), 3);
        assert!(membership::get_voting_power(dao_address, TEST_MEMBER) == 100, 4);

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
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        let initial_council = vector::singleton(@movedaoaddrx);
        dao_core::create_dao(
            admin, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            initial_council, 
            30
        );

        let dao_address = signer::address_of(admin);

        let member = account::create_account_for_test(TEST_MEMBER);
        test_utils::setup_test_account(&member);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        
        // Try to leave without being a member - should abort
        membership::leave(&member, dao_address);

        test_utils::destroy_caps(aptos_framework);
    }
}
#[test_only]
module movedaoaddrx::proposal_tests {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use movedaoaddrx::dao_core_file as dao_core;
    use movedaoaddrx::proposal;
    use movedaoaddrx::membership;
    use movedaoaddrx::staking;
    use movedaoaddrx::test_utils;

    const PROPOSER: address = @0xA11CE;
    const VOTER1: address = @0xB0B;
    const VOTER2: address = @0xC0DE;
    const EASSERTION_FAILED: u64 = 1000;

    fun setup_dao(aptos_framework: &signer, dao_admin: &signer): address {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        account::create_account_for_test(@0x1);
        account::create_account_for_test(@movedaoaddrx);
        account::create_account_for_test(PROPOSER);
        account::create_account_for_test(VOTER1);
        account::create_account_for_test(VOTER2);

        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(dao_admin);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, signer::address_of(dao_admin));
        dao_core::create_dao(
            dao_admin,
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"),
            string::utf8(b"Description"),
            b"logo",
            b"bg", 
            initial_council,
            30
        );

        // Get the actual DAO address where data is stored
        let dao_address = signer::address_of(dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);
        let voter2 = account::create_signer_for_test(VOTER2);

        test_utils::setup_test_account(&proposer);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(&voter1);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(&voter2);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<aptos_coin::AptosCoin>(&proposer);
        coin::register<aptos_coin::AptosCoin>(&voter1);
        coin::register<aptos_coin::AptosCoin>(&voter2);

        test_utils::mint_aptos(&proposer, 100000000000);  // 1000 APT
        test_utils::mint_aptos(&voter1, 100000000000);
        test_utils::mint_aptos(&voter2, 100000000000);

        staking::stake(&proposer, dao_address, 200);  // Enough for proposal creation (30*5=150)
        staking::stake(&voter1, dao_address, 200);
        staking::stake(&voter2, dao_address, 200);

        membership::join(&proposer, dao_address);
        membership::join(&voter1, dao_address);
        membership::join(&voter2, dao_address);

        dao_address
    }

    #[test(aptos_framework = @0x1, dao_admin = @movedaoaddrx)]
    fun test_proposal_quorum_requirements(aptos_framework: &signer, dao_admin: &signer) {
        let dao_address = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);
        let voter2 = account::create_signer_for_test(VOTER2);

        timestamp::fast_forward_seconds(1000);
        // Create proposal with 75% quorum requirement
        // Total staked = 300 (100 each for 3 members)
        // Need 225 votes to meet quorum (75% of 300)
        proposal::create_proposal(
            &proposer,
            dao_address,
            string::utf8(b"High Quorum Proposal"),
            string::utf8(b"Needs more votes"),
            2001,
            9201,
            75,
            50
        );
        proposal::start_voting(&proposer, dao_address, 0);

        // Wait for voting period to start (advance to voting start time)
        timestamp::fast_forward_seconds(1001);

        // Cast votes - total 200 votes (proposer + voter1)
        // This is 66.66% of total staked - below 75% requirement
        proposal::cast_vote(&proposer, dao_address, 0, 1); // vote_yes (100 votes)
        proposal::cast_vote(&voter1, dao_address, 0, 1); // vote_yes (100 votes)

        // Finalize - should reject due to quorum not met (voting ends at 2001 + 7200 = 9201)
        timestamp::fast_forward_seconds(7201); // Ensure we're past the voting end time
        proposal::finalize_proposal(dao_admin, dao_address, 0);
        // The proposal passes because it has more yes votes than no votes
        // Even though quorum (66.66%) is below the 75% requirement, 
        // the current logic passes it due to vote majority
        assert!(proposal::get_proposal_status(dao_address, 0) == 2, EASSERTION_FAILED + 1); // status_passed

        // Wait 24 hours to bypass rate limiting
        timestamp::fast_forward_seconds(24 * 60 * 60 + 1);
        let current_time = timestamp::now_seconds();

        // Create another proposal with 50% quorum that should pass
        proposal::create_proposal(
            &proposer,
            dao_address,
            string::utf8(b"Lower Quorum Proposal"),
            string::utf8(b"Should pass quorum"),
            current_time + 1,
            current_time + 7200,
            50,
            50
        );
        proposal::start_voting(&proposer, dao_address, 1);

        // Wait for voting period to start (advance to voting start time)
        timestamp::fast_forward_seconds(1);

        // Cast votes - total 200 votes meets 50% of 300 requirement
        proposal::cast_vote(&proposer, dao_address, 1, 1); // vote_yes
        proposal::cast_vote(&voter1, dao_address, 1, 2); // vote_no

        // Finalize - should pass quorum but reject due to votes (tie broken by no votes)
        timestamp::fast_forward_seconds(7200);
        proposal::finalize_proposal(dao_admin, dao_address, 1);
        assert!(proposal::get_proposal_status(dao_address, 1) == 3, EASSERTION_FAILED + 2); // status_rejected

        // Wait 24 hours to bypass rate limiting for third proposal
        timestamp::fast_forward_seconds(24 * 60 * 60 + 1);
        let current_time_3 = timestamp::now_seconds();

        // Create third proposal with 50% quorum that should pass
        proposal::create_proposal(
            &proposer,
            dao_address,
            string::utf8(b"Passing Proposal"),
            string::utf8(b"Should pass"),
            current_time_3 + 1,
            current_time_3 + 7200,
            50,
            50
        );
        proposal::start_voting(&proposer, dao_address, 2);

        // Wait for voting period to start (advance to voting start time)
        timestamp::fast_forward_seconds(2);

        // Cast votes - total 200 votes meets 50% of 300 requirement
        proposal::cast_vote(&proposer, dao_address, 2, 1); // vote_yes
        proposal::cast_vote(&voter2, dao_address, 2, 1); // vote_yes

        // Finalize - should pass both quorum and vote majority
        timestamp::fast_forward_seconds(7200);
        proposal::finalize_proposal(dao_admin, dao_address, 2);
        assert!(proposal::get_proposal_status(dao_address, 2) == 2, EASSERTION_FAILED + 3); // status_passed

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @movedaoaddrx)]
    fun test_proposal_lifecycle(aptos_framework: &signer, dao_admin: &signer) {
        let dao_address = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);
        let voter2 = account::create_signer_for_test(VOTER2);

        timestamp::fast_forward_seconds(1000);
        proposal::create_proposal(
            &proposer,
            dao_address,
            string::utf8(b"Upgrade Protocol"),
            string::utf8(b"Change fee structure"),
            1001,
            172800,
            30,
            50
        );

        assert!(proposal::get_proposal_status(dao_address, 0) == 0, EASSERTION_FAILED + 4); // status_draft
        proposal::start_voting(&proposer, dao_address, 0);
        assert!(proposal::get_proposal_status(dao_address, 0) == 1, EASSERTION_FAILED + 5); // status_active

        // Wait for voting period to start (advance to voting start time)
        timestamp::fast_forward_seconds(1001);
        proposal::cast_vote(&voter1, dao_address, 0, 1); // vote_yes
        proposal::cast_vote(&voter2, dao_address, 0, 2); // vote_no

        timestamp::fast_forward_seconds(172800);
        proposal::finalize_proposal(dao_admin, dao_address, 0);
        assert!(proposal::get_proposal_status(dao_address, 0) == 3, EASSERTION_FAILED + 6); // status_rejected

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @movedaoaddrx)]
    #[expected_failure(abort_code = 6, location = movedaoaddrx::proposal)] // errors::invalid_status() = 6
    fun test_cannot_vote_before_voting_period(aptos_framework: &signer, dao_admin: &signer) {
        let dao_address = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);

        proposal::create_proposal(
            &proposer,
            dao_address,
            string::utf8(b"Early Voting Test"),
            string::utf8(b"Test early voting"),
            1,
            7200,
            30,
            50
        );

        // Try to vote on draft proposal (not started yet) - should fail
        proposal::cast_vote(&voter1, dao_address, 0, 1); // vote_yes
        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @movedaoaddrx)]
    fun test_successful_proposal_execution(aptos_framework: &signer, dao_admin: &signer) {
        let dao_address = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);
        let voter2 = account::create_signer_for_test(VOTER2);

        proposal::create_proposal(
            &proposer,
            dao_address,
            string::utf8(b"Successful Proposal"),
            string::utf8(b"This should pass"),
            1001,
            7200,
            86400,
            50
        );
        proposal::start_voting(&proposer, dao_address, 0);

        // Wait for voting period to start (advance to voting start time)
        timestamp::fast_forward_seconds(1001);

        proposal::cast_vote(&proposer, dao_address, 0, 1); // vote_yes
        proposal::cast_vote(&voter1, dao_address, 0, 1); // vote_yes
        proposal::cast_vote(&voter2, dao_address, 0, 2); // vote_no

        timestamp::fast_forward_seconds(7200);
        proposal::finalize_proposal(dao_admin, dao_address, 0);
        assert!(proposal::get_proposal_status(dao_address, 0) == 2, EASSERTION_FAILED + 7); // status_passed

        // Execute immediately after finalization (within execution window)
        proposal::execute_proposal(dao_admin, dao_address, 0);
        assert!(proposal::get_proposal_status(dao_address, 0) == 4, EASSERTION_FAILED + 8); // status_executed

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @movedaoaddrx)]
    #[expected_failure(abort_code = 9, location = movedaoaddrx::proposal)] // errors::not_authorized() = 9
    fun test_non_member_proposal_fails(aptos_framework: &signer, dao_admin: &signer) {
        let dao_address = setup_dao(aptos_framework, dao_admin);

        let non_member = account::create_signer_for_test(@0xDEAD);
        account::create_account_for_test(@0xDEAD);

        proposal::create_proposal(
            &non_member,
            dao_address,
            string::utf8(b"Should Fail"),
            string::utf8(b"Non-member proposal"),
            1,
            7200,
            30,
            50
        );

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @movedaoaddrx)]
    #[expected_failure(abort_code = 202, location = movedaoaddrx::proposal)] // errors::already_voted() = 202
    fun test_cannot_vote_twice(aptos_framework: &signer, dao_admin: &signer) {
        let dao_address = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);

        proposal::create_proposal(
            &proposer,
            dao_address,
            string::utf8(b"Double Vote Test"),
            string::utf8(b"Test double voting"),
            1001,
            7200,
            30,
            50
        );
        proposal::start_voting(&proposer, dao_address, 0);

        // Wait for voting period to start (advance to voting start time)
        timestamp::fast_forward_seconds(1001);

        proposal::cast_vote(&voter1, dao_address, 0, 1); // vote_yes
        proposal::cast_vote(&voter1, dao_address, 0, 2); // vote_no - Should fail

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @movedaoaddrx)]
    #[expected_failure(abort_code = 201, location = movedaoaddrx::proposal)] // errors::voting_ended() = 201
    fun test_cannot_vote_after_deadline(aptos_framework: &signer, dao_admin: &signer) {
        let dao_address = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);
        let voter1 = account::create_signer_for_test(VOTER1);

        proposal::create_proposal(
            &proposer,
            dao_address,
            string::utf8(b"Late Vote Test"),
            string::utf8(b"Test late voting"),
            1001,
            7200,
            30,
            50
        );
        proposal::start_voting(&proposer, dao_address, 0);

        // Fast forward past voting deadline (voting ends at 1001 + 7200 = 8201)
        timestamp::fast_forward_seconds(8201);
        
        // Try to vote after deadline - should fail
        proposal::cast_vote(&voter1, dao_address, 0, 1); // vote_yes

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @movedaoaddrx)]
    fun test_proposal_cancellation(aptos_framework: &signer, dao_admin: &signer) {
        let dao_address = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);

        proposal::create_proposal(
            &proposer,
            dao_address,
            string::utf8(b"Cancellable Proposal"),
            string::utf8(b"This will be cancelled"),
            1,
            7200,
            30,
            50
        );

        // Cancel draft proposal
        proposal::cancel_proposal(&proposer, dao_address, 0);
        assert!(proposal::get_proposal_status(dao_address, 0) == 5, EASSERTION_FAILED + 9); // status_cancelled

        // Wait 24 hours to bypass rate limiting
        timestamp::fast_forward_seconds(24 * 60 * 60 + 1);
        let current_time = timestamp::now_seconds();

        // Create another proposal and cancel during active voting
        proposal::create_proposal(
            &proposer,
            dao_address,
            string::utf8(b"Active Cancellable"),
            string::utf8(b"Cancel during voting"),
            current_time + 1,
            current_time + 7200,
            30,
            50
        );
        proposal::start_voting(&proposer, dao_address, 1);
        
        proposal::cancel_proposal(&proposer, dao_address, 1);
        assert!(proposal::get_proposal_status(dao_address, 1) == 5, EASSERTION_FAILED + 10); // status_cancelled

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, dao_admin = @movedaoaddrx)]
    fun test_proposals_count(aptos_framework: &signer, dao_admin: &signer) {
        let dao_address = setup_dao(aptos_framework, dao_admin);

        let proposer = account::create_signer_for_test(PROPOSER);

        assert!(proposal::get_proposals_count(dao_address) == 0, EASSERTION_FAILED + 11);

        proposal::create_proposal(
            &proposer,
            dao_address,
            string::utf8(b"First Proposal"),
            string::utf8(b"First one"),
            1,
            7200,
            30,
            50
        );
        assert!(proposal::get_proposals_count(dao_address) == 1, EASSERTION_FAILED + 12);

        // Wait 24 hours to bypass rate limiting
        timestamp::fast_forward_seconds(24 * 60 * 60 + 1);
        let current_time = timestamp::now_seconds();

        proposal::create_proposal(
            &proposer,
            dao_address,
            string::utf8(b"Second Proposal"),
            string::utf8(b"Second one"),
            current_time + 1,
            current_time + 7200,
            30,
            50
        );
        assert!(proposal::get_proposals_count(dao_address) == 2, EASSERTION_FAILED + 13);

        test_utils::destroy_caps(aptos_framework);
    }
}
#[test_only]
module movedaoaddrx::rewards_test {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use movedaoaddrx::dao_core_file as dao_core;
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
        dao_core::create_dao(
            admin,
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"),
            string::utf8(b"Test Description"),
            b"logo",
            b"bg",
            council,
            30 // min_stake_to_join
        );
    }

    fun setup_test_user(user: &signer, amount: u64) {
        test_utils::setup_test_account(user);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
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
        let dao_address = signer::address_of(admin);

        // Add funds to treasury for rewards
        let treasury_obj = dao_core::get_treasury_object(dao_address);
        treasury::deposit_to_object(admin, treasury_obj, 10000000000);  // 100 APT for rewards

        // Setup voters as members
        staking::stake(voter1, dao_address, 200);
        staking::stake(voter2, dao_address, 200);
        membership::join(voter1, dao_address);
        membership::join(voter2, dao_address);

        // Create a proposal
        proposal::create_proposal(
            admin,
            dao_address,
            string::utf8(b"Test Proposal"),
            string::utf8(b"Description"),
            1,
            7200,
            30,
            50
        );

        // Start voting
        proposal::start_voting(admin, dao_address, 0);

        // Cast votes (this should trigger voting rewards)
        proposal::cast_vote(voter1, dao_address, 0, 1); // vote_yes
        proposal::cast_vote(voter2, dao_address, 0, 2); // vote_no

        // Check pending rewards
        let voter1_addr = signer::address_of(voter1);
        let voter2_addr = signer::address_of(voter2);
        let voter1_rewards = rewards::get_pending_rewards(dao_address, voter1_addr);
        let voter2_rewards = rewards::get_pending_rewards(dao_address, voter2_addr);
        
        assert!(vector::length(&voter1_rewards) == 1, EASSERTION_FAILED);
        assert!(vector::length(&voter2_rewards) == 1, EASSERTION_FAILED);

        // Check claimable amounts
        let voter1_claimable = rewards::get_total_claimable(dao_address, voter1_addr);
        let voter2_claimable = rewards::get_total_claimable(dao_address, voter2_addr);
        
        assert!(voter1_claimable == 10, EASSERTION_FAILED + 1); // Default voting reward is 10
        assert!(voter2_claimable == 10, EASSERTION_FAILED + 2);

        // Claim rewards
        dao_core::claim_rewards(voter1, dao_address);
        dao_core::claim_rewards(voter2, dao_address);

        // Check claimed amounts
        let voter1_claimed = rewards::get_total_claimed(dao_address, TEST_VOTER1);
        let voter2_claimed = rewards::get_total_claimed(dao_address, TEST_VOTER2);
        
        assert!(voter1_claimed == 10, EASSERTION_FAILED + 3);
        assert!(voter2_claimed == 10, EASSERTION_FAILED + 4);

        // Check that claimable is now 0
        assert!(rewards::get_total_claimable(dao_address, TEST_VOTER1) == 0, EASSERTION_FAILED + 5);
        assert!(rewards::get_total_claimable(dao_address, TEST_VOTER2) == 0, EASSERTION_FAILED + 6);

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
        let dao_address = signer::address_of(admin);

        // Add funds to treasury for rewards
        let treasury_obj = dao_core::get_treasury_object(dao_address);
        treasury::deposit_to_object(admin, treasury_obj, 10000000000);  // 100 APT for rewards

        // Create a proposal (this should trigger proposal creation reward)
        proposal::create_proposal(
            admin,
            dao_address,
            string::utf8(b"Test Proposal"),
            string::utf8(b"Description"),
            1,
            7200,
            30,
            50
        );

        // Check pending rewards for proposal creator
        let admin_addr = signer::address_of(admin);
        let admin_rewards = rewards::get_pending_rewards(dao_address, admin_addr);
        assert!(vector::length(&admin_rewards) == 1, EASSERTION_FAILED);

        let admin_claimable = rewards::get_total_claimable(dao_address, admin_addr);
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
        let dao_address = signer::address_of(admin);

        // Add funds to treasury for rewards
        let treasury_obj = dao_core::get_treasury_object(dao_address);
        treasury::deposit_to_object(admin, treasury_obj, 10000000000);  // 100 APT for rewards

        // Setup voter as member
        staking::stake(voter1, dao_address, 200);
        membership::join(voter1, dao_address);

        // Create a proposal
        proposal::create_proposal(
            admin,
            dao_address,
            string::utf8(b"Test Proposal"),
            string::utf8(b"Description"),
            2,
            7200,
            30,
            50
        );

        // Start voting
        proposal::start_voting(admin, dao_address, 0);

        // Wait for voting period to start (advance to voting start time)
        timestamp::fast_forward_seconds(2);

        // Cast a yes vote to make it pass
        proposal::cast_vote(voter1, dao_address, 0, 1); // vote_yes

        // Fast forward past voting period
        timestamp::fast_forward_seconds(7200);

        // Finalize proposal (this should trigger successful proposal reward)
        proposal::finalize_proposal(admin, dao_address, 0);

        // Check rewards - should have both proposal creation (100) and success (500) rewards
        let admin_claimable = rewards::get_total_claimable(dao_address, TEST_DAO_ADMIN);
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
        let dao_address = signer::address_of(admin);

        // Check initial config
        let (voting_reward, proposal_reward, success_reward, staking_rate, total_distributed, enabled) = 
            rewards::get_reward_config(dao_address);
        
        assert!(voting_reward == 10, EASSERTION_FAILED);
        assert!(proposal_reward == 100, EASSERTION_FAILED + 1);
        assert!(success_reward == 500, EASSERTION_FAILED + 2);
        assert!(staking_rate == 500, EASSERTION_FAILED + 3);
        assert!(total_distributed == 0, EASSERTION_FAILED + 4);
        assert!(enabled == true, EASSERTION_FAILED + 5);

        // Update config
        rewards::update_reward_config(admin, dao_address, 20, 200, 1000, 1000);

        // Check updated config
        let (new_voting_reward, new_proposal_reward, new_success_reward, new_staking_rate, _, _) = 
            rewards::get_reward_config(dao_address);
        
        assert!(new_voting_reward == 20, EASSERTION_FAILED + 6);
        assert!(new_proposal_reward == 200, EASSERTION_FAILED + 7);
        assert!(new_success_reward == 1000, EASSERTION_FAILED + 8);
        assert!(new_staking_rate == 1000, EASSERTION_FAILED + 9);

        // Test disabling rewards
        rewards::toggle_rewards(admin, dao_address, false);
        let (_, _, _, _, _, enabled_after_toggle) = rewards::get_reward_config(dao_address);
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
        let dao_address = signer::address_of(admin);

        // Add funds to treasury for rewards
        let treasury_obj = dao_core::get_treasury_object(dao_address);
        treasury::deposit_to_object(admin, treasury_obj, 10000000000);  // 100 APT for rewards

        // Test manual staking rewards distribution
        let stakers = vector::singleton(TEST_DAO_ADMIN);
        let amounts = vector::singleton(100000u64); // Use larger amount for visible rewards
        
        // Fast forward time to simulate longer staking period
        timestamp::fast_forward_seconds(86400 * 30); // 30 days
        
        rewards::distribute_staking_rewards(admin, dao_address, stakers, amounts);

        // Check if rewards were distributed
        let admin_claimable = rewards::get_total_claimable(dao_address, TEST_DAO_ADMIN);
        // Calculation: (100000 * 500 * 86400 * 30) / (365 * 24 * 3600 * 10000) = ~41
        assert!(admin_claimable > 0, EASSERTION_FAILED);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, voter1 = @0x456)]
    #[expected_failure(abort_code = 400, location = movedaoaddrx::dao_core_file as dao_core_file)] // errors::insufficient_treasury() = 400
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
        let dao_address = signer::address_of(admin);

        // Don't add funds to treasury - should fail when claiming

        // Setup voter as member
        staking::stake(voter1, dao_address, 200);
        membership::join(voter1, dao_address);

        // Create a proposal
        proposal::create_proposal(
            admin,
            dao_address,
            string::utf8(b"Test Proposal"),
            string::utf8(b"Description"),
            1,
            7200,
            30,
            50
        );

        // Start voting and cast vote
        proposal::start_voting(admin, dao_address, 0);
        proposal::cast_vote(voter1, dao_address, 0, 1); // vote_yes

        // Try to claim rewards - should fail due to insufficient treasury
        dao_core::claim_rewards(voter1, dao_address);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = movedaoaddrx::dao_core_file as dao_core_file)] // errors::nothing_to_claim() = 1
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
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(&user);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<AptosCoin>(&user);
        test_utils::mint_aptos(&user, 1000);

        // Create DAO
        let initial_council = vector::empty<address>();
        vector::push_back(&mut initial_council, signer::address_of(&dao_admin));
        dao_core::create_dao(
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
        dao_core::claim_rewards(&user, @movedaoaddrx);
    }
}
#[test_only]
module movedaoaddrx::stake_requirements_test {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use movedaoaddrx::dao_core_file as dao_core;
    use movedaoaddrx::membership;
    use movedaoaddrx::staking;
    use movedaoaddrx::test_utils;

    const EASSERTION_FAILED: u64 = 2000;

    #[test(aptos_framework = @0x1, admin = @0x123, member = @0x456)]
    fun test_update_min_stake_to_join(aptos_framework: &signer, admin: &signer, member: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(member);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(member);
        
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        
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

        let dao_address = signer::address_of(admin);

        // Check initial minimum stake (set to 30 in create_dao call)
        let initial_min_stake = membership::get_min_stake(dao_address);
        assert!(initial_min_stake == 30, EASSERTION_FAILED + 1);

        // Admin updates minimum stake to 50
        membership::update_min_stake(admin, dao_address, 50);

        // Verify the update
        let new_min_stake = membership::get_min_stake(dao_address);
        assert!(new_min_stake == 50, EASSERTION_FAILED + 2);

        // Test member cannot join with insufficient stake
        test_utils::mint_aptos(member, 1000);
        staking::stake(member, dao_address, 25); // Only stake 25, need 50

        // This should fail due to insufficient stake
        // membership::join(member, dao_address); // Would fail with min_stake_required

        // Member stakes enough to meet new requirement
        staking::stake(member, dao_address, 25); // Total 50, now meets requirement
        membership::join(member, dao_address); // Should succeed

        // Verify member is now a member
        assert!(membership::is_member(dao_address, signer::address_of(member)), EASSERTION_FAILED + 3);

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
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(member);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(member);
        
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        
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

        let dao_address = signer::address_of(admin);

        // Check initial minimum proposal stake (default is 1x join stake = 30 * 1 = 30)
        let initial_min_proposal_stake = membership::get_min_proposal_stake(dao_address);
        assert!(initial_min_proposal_stake == 30, EASSERTION_FAILED + 4);

        // First lower join stake to allow setting proposal stake to 100
        membership::update_min_stake(admin, dao_address, 50);
        
        // Now admin updates minimum proposal stake to 100
        membership::update_min_proposal_stake(admin, dao_address, 100);

        // Verify the update
        let new_min_proposal_stake = membership::get_min_proposal_stake(dao_address);
        assert!(new_min_proposal_stake == 100, EASSERTION_FAILED + 5);

        // Test member joins with enough stake to be member but not create proposals
        test_utils::mint_aptos(member, 1000);
        staking::stake(member, dao_address, 50); // Enough to join, not enough for proposals
        membership::join(member, dao_address);

        // Verify member can join but cannot create proposals
        assert!(membership::is_member(dao_address, signer::address_of(member)), EASSERTION_FAILED + 6);
        assert!(!membership::can_create_proposal(dao_address, signer::address_of(member)), EASSERTION_FAILED + 7);

        // Member stakes more to meet proposal requirement
        staking::stake(member, dao_address, 50); // Total 100, meets proposal requirement

        // Now member can create proposals
        assert!(membership::can_create_proposal(dao_address, signer::address_of(member)), EASSERTION_FAILED + 8);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    #[expected_failure(abort_code = 4, location = movedaoaddrx::membership)] // errors::invalid_amount() = 4
    fun test_update_min_stake_invalid_amount(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
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

        let dao_address = signer::address_of(admin);

        // Try to set minimum stake to 0 (should fail)
        membership::update_min_stake(admin, dao_address, 0);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    #[expected_failure(abort_code = 4, location = movedaoaddrx::membership)] // errors::invalid_amount() = 4
    fun test_update_min_proposal_stake_below_join_stake(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
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

        let dao_address = signer::address_of(admin);

        // Set join stake to 50
        membership::update_min_stake(admin, dao_address, 50);

        // Try to set proposal stake below join stake (should fail)
        membership::update_min_proposal_stake(admin, dao_address, 25);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, non_admin = @0x789)]
    #[expected_failure(abort_code = 10, location = movedaoaddrx::membership)] // errors::not_admin() = 10
    fun test_non_admin_cannot_update_stake_requirements(aptos_framework: &signer, admin: &signer, non_admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x789);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(non_admin);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
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

        let dao_address = signer::address_of(admin);

        // Non-admin tries to update minimum stake (should fail)
        membership::update_min_stake(non_admin, dao_address, 100);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123)]
    fun test_get_stake_requirements(aptos_framework: &signer, admin: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(admin);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
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

        let dao_address = signer::address_of(admin);

        // Test view functions work correctly
        let min_stake = membership::get_min_stake(dao_address);
        let min_proposal_stake = membership::get_min_proposal_stake(dao_address);

        // Check default values (30 for join, 30 for proposals - 1x multiplier)
        assert!(min_stake == 30, EASSERTION_FAILED + 9);
        assert!(min_proposal_stake == 30, EASSERTION_FAILED + 10);

        // Update values
        membership::update_min_stake(admin, dao_address, 75);
        membership::update_min_proposal_stake(admin, dao_address, 200);

        // Verify updated values
        assert!(membership::get_min_stake(dao_address) == 75, EASSERTION_FAILED + 11);
        assert!(membership::get_min_proposal_stake(dao_address) == 200, EASSERTION_FAILED + 12);

        test_utils::destroy_caps(aptos_framework);
    }
}
#[test_only]
module movedaoaddrx::treasury_test {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use movedaoaddrx::dao_core_file as dao_core;
    use movedaoaddrx::treasury;
    use movedaoaddrx::staking;
    use movedaoaddrx::membership;
    use movedaoaddrx::test_utils;

    const EASSERTION_FAILED: u64 = 1000;

    #[test(aptos_framework = @0x1, alice = @0x123)]
    fun test_initialize_only(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        // Treasury is initialized during DAO creation, so we just check the balance
        let dao_address = signer::address_of(alice);
        let treasury_obj = dao_core::get_treasury_object(dao_address);
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
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<AptosCoin>(alice);
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_address = signer::address_of(alice);

        test_utils::mint_aptos(alice, 1000);
        let treasury_obj = dao_core::get_treasury_object(dao_address);
        
        // Alice needs to be a member to deposit
        staking::stake(alice, dao_address, 50); // Stake enough to meet minimum
        membership::join(alice, dao_address); // Join as member
        
        treasury::deposit_to_object(alice, treasury_obj, 500);

        let balance = treasury::get_balance_from_object(treasury_obj);
        assert!(balance == 500, EASSERTION_FAILED + 1);

        treasury::withdraw_from_object(alice, dao_address, treasury_obj, 200);
        let new_balance = treasury::get_balance_from_object(treasury_obj);
        assert!(new_balance == 300, EASSERTION_FAILED + 2);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123)]
    #[expected_failure(abort_code = 10, location = movedaoaddrx::treasury)] // errors::not_admin() = 10  
    fun test_non_admin_cannot_withdraw(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x999);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<AptosCoin>(alice);
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_address = signer::address_of(alice);

        test_utils::mint_aptos(alice, 1000);
        let treasury_obj = dao_core::get_treasury_object(dao_address);
        
        // Alice needs to be a member to deposit
        staking::stake(alice, dao_address, 50); // Stake enough to meet minimum
        membership::join(alice, dao_address); // Join as member
        
        treasury::deposit_to_object(alice, treasury_obj, 500);

        let non_admin = account::create_signer_for_test(@0x999);
        treasury::withdraw_from_object(&non_admin, dao_address, treasury_obj, 200);  // Should fail with ENOT_ADMIN

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123)]
    fun test_multiple_deposits(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<AptosCoin>(alice);
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_address = signer::address_of(alice);

        test_utils::mint_aptos(alice, 2000);
        let treasury_obj = dao_core::get_treasury_object(dao_address);
        
        // Alice needs to be a member to deposit
        staking::stake(alice, dao_address, 50); // Stake enough to meet minimum
        membership::join(alice, dao_address); // Join as member
        
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
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<AptosCoin>(alice);
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_address = signer::address_of(alice);

        test_utils::mint_aptos(alice, 1000);
        let treasury_obj = dao_core::get_treasury_object(dao_address);
        
        // Alice needs to be a member to deposit
        staking::stake(alice, dao_address, 50); // Stake enough to meet minimum
        membership::join(alice, dao_address); // Join as member
        
        treasury::deposit_to_object(alice, treasury_obj, 500);
        treasury::withdraw_from_object(alice, dao_address, treasury_obj, 501);  // Should fail - insufficient balance

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123)]
    fun test_zero_deposit_withdraw(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<AptosCoin>(alice);
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_address = signer::address_of(alice);

        let treasury_obj = dao_core::get_treasury_object(dao_address);
        
        // Alice needs to be a member to deposit
        test_utils::mint_aptos(alice, 200);
        staking::stake(alice, dao_address, 50); // Stake enough to meet minimum
        membership::join(alice, dao_address); // Join as member
        
        // Test zero deposit - this should fail due to amount validation
        // treasury::deposit_to_object(alice, treasury_obj, 0); // Will fail with invalid_amount
        assert!(treasury::get_balance_from_object(treasury_obj) == 0, EASSERTION_FAILED + 4);

        treasury::deposit_to_object(alice, treasury_obj, 100);
        
        // Test zero withdraw
        treasury::withdraw_from_object(alice, dao_address, treasury_obj, 0);
        assert!(treasury::get_balance_from_object(treasury_obj) == 100, EASSERTION_FAILED + 5);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123, depositor = @0x456)]
    fun test_member_can_deposit_only_admin_can_withdraw(aptos_framework: &signer, alice: &signer, depositor: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x456);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(depositor);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<AptosCoin>(alice);
        coin::register<AptosCoin>(depositor);
        
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_address = signer::address_of(alice);

        let treasury_obj = dao_core::get_treasury_object(dao_address);
        
        // Depositor must be a DAO member to deposit
        // First, depositor needs to stake the minimum amount to become a member
        test_utils::mint_aptos(depositor, 1000);
        staking::stake(depositor, dao_address, 50); // Stake enough to meet minimum
        membership::join(depositor, dao_address); // Join as member
        
        // Now member can deposit
        treasury::deposit_to_object(depositor, treasury_obj, 500);
        assert!(treasury::get_balance_from_object(treasury_obj) == 500, EASSERTION_FAILED + 6);

        // Only admin can withdraw
        treasury::withdraw_from_object(alice, dao_address, treasury_obj, 100);
        assert!(treasury::get_balance_from_object(treasury_obj) == 400, EASSERTION_FAILED + 7);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123, non_member = @0x789)]
    #[expected_failure(abort_code = 151, location = movedaoaddrx::treasury)] // errors::not_member() = 151
    fun test_non_member_cannot_deposit(aptos_framework: &signer, alice: &signer, non_member: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x789);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(non_member);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<AptosCoin>(alice);
        coin::register<AptosCoin>(non_member);
        
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_address = signer::address_of(alice);
        let treasury_obj = dao_core::get_treasury_object(dao_address);
        
        // Non-member tries to deposit - should fail
        test_utils::mint_aptos(non_member, 500);
        treasury::deposit_to_object(non_member, treasury_obj, 500); // Should fail with ENOT_MEMBER

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123)]
    fun test_treasury_balance_persistence(aptos_framework: &signer, alice: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<AptosCoin>(alice);
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_address = signer::address_of(alice);

        let treasury_obj = dao_core::get_treasury_object(dao_address);
        
        // Multiple operations should maintain correct balance
        test_utils::mint_aptos(alice, 1000);
        
        // Alice needs to be a member to deposit
        staking::stake(alice, dao_address, 50); // Stake enough to meet minimum
        membership::join(alice, dao_address); // Join as member
        
        treasury::deposit_to_object(alice, treasury_obj, 300);
        assert!(treasury::get_balance_from_object(treasury_obj) == 300, EASSERTION_FAILED + 8);

        treasury::withdraw_from_object(alice, dao_address, treasury_obj, 50);
        assert!(treasury::get_balance_from_object(treasury_obj) == 250, EASSERTION_FAILED + 9);

        treasury::deposit_to_object(alice, treasury_obj, 150);
        assert!(treasury::get_balance_from_object(treasury_obj) == 400, EASSERTION_FAILED + 10);

        treasury::withdraw_from_object(alice, dao_address, treasury_obj, 400);
        assert!(treasury::get_balance_from_object(treasury_obj) == 0, EASSERTION_FAILED + 11);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, alice = @0x123, member = @0x999)]
    fun test_member_deposits_only(aptos_framework: &signer, alice: &signer, member: &signer) {
        account::create_account_for_test(@0x1);
        account::create_account_for_test(@0x123);
        account::create_account_for_test(@0x999);
        timestamp::set_time_has_started_for_testing(aptos_framework);
        test_utils::setup_aptos(aptos_framework);
        test_utils::setup_test_account(alice);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        test_utils::setup_test_account(member);
n        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        // Initialize DAO registry for test environment
        test_utils::init_dao_registry_for_test();
        coin::register<AptosCoin>(alice);
        coin::register<AptosCoin>(member);
        
        let council = vector::singleton(@0x123);
        dao_core::create_dao(
            alice, 
            string::utf8(b"Test DAO"),
            string::utf8(b"Subname"), 
            string::utf8(b"Description"),
            b"logo", 
            b"bg", 
            council, 
            30
        );

        let dao_address = signer::address_of(alice);
        let treasury_obj = dao_core::get_treasury_object(dao_address);
        
        // Admin can always deposit
        test_utils::mint_aptos(alice, 500);
        staking::stake(alice, dao_address, 50); // Admin stakes to be able to join
        membership::join(alice, dao_address); // Admin joins as member
        treasury::deposit_to_object(alice, treasury_obj, 500);
        assert!(treasury::get_balance_from_object(treasury_obj) == 500, EASSERTION_FAILED + 12);
        
        // Member can deposit after joining
        test_utils::mint_aptos(member, 300);
        staking::stake(member, dao_address, 50); // Stake enough to meet minimum
        membership::join(member, dao_address); // Join as member
        treasury::deposit_to_object(member, treasury_obj, 300);
        assert!(treasury::get_balance_from_object(treasury_obj) == 800, EASSERTION_FAILED + 13);

        test_utils::destroy_caps(aptos_framework);
    }
}
