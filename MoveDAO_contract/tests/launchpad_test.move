#[test_only]
module dao_addr::launchpad_test {
    use std::vector;
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use dao_addr::dao_core;
    use dao_addr::launchpad;
    use dao_addr::test_utils;

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
            string::utf8(b"Test Description"),
            b"logo",
            b"bg",
            council,
            30, // min_quorum_percent
            3600, // min_voting_period
            86400 // max_voting_period
        );
    }

    fun setup_test_user(user: &signer, amount: u64) {
        test_utils::setup_test_account(user);
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
        let dao_addr = signer::address_of(admin);

        // Create launchpad
        dao_core::create_dao_launchpad(
            admin,
            dao_addr,
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
            launchpad::get_launchpad_info(dao_addr);
        
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
        let dao_addr = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_addr, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
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
        
        dao_core::manage_launchpad_whitelist(admin, dao_addr, participants, tiers, allocations);

        // Check whitelist status
        assert!(launchpad::is_whitelisted(dao_addr, TEST_INVESTOR1), EASSERTION_FAILED);
        assert!(launchpad::is_whitelisted(dao_addr, TEST_INVESTOR2), EASSERTION_FAILED + 1);
        assert!(!launchpad::is_whitelisted(dao_addr, TEST_INVESTOR3), EASSERTION_FAILED + 2);

        // Check whitelist details
        let (tier1, allocation1, kyc1) = launchpad::get_whitelist_info(dao_addr, TEST_INVESTOR1);
        let (tier2, allocation2, kyc2) = launchpad::get_whitelist_info(dao_addr, TEST_INVESTOR2);
        
        assert!(tier1 == launchpad::tier_gold(), EASSERTION_FAILED + 3);
        assert!(allocation1 == 5000, EASSERTION_FAILED + 4);
        assert!(kyc1 == false, EASSERTION_FAILED + 5); // Not verified yet
        
        assert!(tier2 == launchpad::tier_silver(), EASSERTION_FAILED + 6);
        assert!(allocation2 == 3000, EASSERTION_FAILED + 7);
        assert!(kyc2 == false, EASSERTION_FAILED + 8);

        // Update KYC status
        launchpad::update_kyc_status(admin, dao_addr, TEST_INVESTOR1, true);
        let (_, _, kyc1_updated) = launchpad::get_whitelist_info(dao_addr, TEST_INVESTOR1);
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
        let dao_addr = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_addr, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, false
        );

        let now = timestamp::now_seconds();
        
        // Update timeline
        launchpad::update_timeline(
            admin,
            dao_addr,
            now + 100,    // whitelist starts in 100 seconds
            now + 1000,   // presale starts in 1000 seconds
            now + 2000,   // public sale starts in 2000 seconds
            now + 3000,   // sale ends in 3000 seconds
            now + 4000    // vesting starts in 4000 seconds
        );

        // Check timeline
        let (whitelist_start, presale_start, public_start, sale_end, vesting_start) = 
            launchpad::get_timeline(dao_addr);
        
        assert!(whitelist_start == now + 100, EASSERTION_FAILED);
        assert!(presale_start == now + 1000, EASSERTION_FAILED + 1);
        assert!(public_start == now + 2000, EASSERTION_FAILED + 2);
        assert!(sale_end == now + 3000, EASSERTION_FAILED + 3);
        assert!(vesting_start == now + 4000, EASSERTION_FAILED + 4);

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
        let dao_addr = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_addr, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
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
        
        dao_core::manage_launchpad_whitelist(admin, dao_addr, participants, tiers, allocations);

        // Setup timeline for immediate presale
        let now = timestamp::now_seconds();
        launchpad::update_timeline(admin, dao_addr, now + 100, now + 150, now + 1000, now + 2000, now + 3000);

        // Advance time to reach whitelist start
        timestamp::fast_forward_seconds(150);
        
        // Advance to whitelist phase first
        launchpad::advance_phase(admin, dao_addr);
        
        // Advance time to reach presale start
        timestamp::fast_forward_seconds(1000);
        
        // Advance to presale phase
        launchpad::advance_phase(admin, dao_addr);
        
        let (_, _, _, _, phase, _) = launchpad::get_launchpad_info(dao_addr);
        assert!(phase == launchpad::phase_presale(), EASSERTION_FAILED);

        // Make purchases
        launchpad::purchase_tokens(investor1, dao_addr, 2000); // Gold tier buying 2000 tokens
        launchpad::purchase_tokens(investor2, dao_addr, 1500); // Silver tier buying 1500 tokens

        // Check purchase history
        let purchased1 = launchpad::get_purchase_history(dao_addr, TEST_INVESTOR1);
        let purchased2 = launchpad::get_purchase_history(dao_addr, TEST_INVESTOR2);
        
        assert!(purchased1 == 2000, EASSERTION_FAILED + 1);
        assert!(purchased2 == 1500, EASSERTION_FAILED + 2);

        // Check sale stats
        let (tokens_sold, funds_raised, total_available, percentage_sold) = 
            launchpad::get_sale_stats(dao_addr);
        
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
        let dao_addr = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_addr, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, false
        );

        // Setup timeline for public sale
        let now = timestamp::now_seconds();
        launchpad::update_timeline(admin, dao_addr, now + 200, now + 300, now + 350, now + 1500, now + 2000);

        // Advance time to reach whitelist start
        timestamp::fast_forward_seconds(300);
        
        // Advance to whitelist phase first
        launchpad::advance_phase(admin, dao_addr);
        
        // Advance time to reach presale start
        timestamp::fast_forward_seconds(100);
        
        // Advance to presale phase
        launchpad::advance_phase(admin, dao_addr);
        
        // Advance time to reach public sale start
        timestamp::fast_forward_seconds(700);
        
        // Advance to public sale phase
        launchpad::advance_phase(admin, dao_addr);
        
        let (_, _, _, _, phase, _) = launchpad::get_launchpad_info(dao_addr);
        assert!(phase == launchpad::phase_public_sale(), EASSERTION_FAILED);

        // Make public purchase (no whitelist required)
        launchpad::purchase_tokens(investor1, dao_addr, 10000);

        let purchased = launchpad::get_purchase_history(dao_addr, TEST_INVESTOR1);
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
        let dao_addr = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_addr, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, false
        );

        // Create vesting schedule
        launchpad::create_vesting_schedule(
            admin,
            dao_addr,
            TEST_INVESTOR1,
            50000,    // 50k tokens
            2592000,  // 30 days cliff (in seconds)
            31536000  // 365 days vesting (in seconds)
        );

        // Check initial vesting info
        let (total, claimed, claimable) = launchpad::get_vesting_info(dao_addr, TEST_INVESTOR1);
        assert!(total == 50000, EASSERTION_FAILED);
        assert!(claimed == 0, EASSERTION_FAILED + 1);
        assert!(claimable == 0, EASSERTION_FAILED + 2); // Still in cliff period

        // Fast forward past cliff
        timestamp::fast_forward_seconds(2592001); // Just past 30 days

        let (_, _, claimable_after_cliff) = launchpad::get_vesting_info(dao_addr, TEST_INVESTOR1);
        assert!(claimable_after_cliff > 0, EASSERTION_FAILED + 3); // Some tokens should be claimable

        // Claim vested tokens
        launchpad::claim_vested_tokens(beneficiary, dao_addr);

        let (_, claimed_after, _) = launchpad::get_vesting_info(dao_addr, TEST_INVESTOR1);
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
        let dao_addr = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_addr, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, false
        );

        // Check initial state
        let (_, _, _, _, _, is_active) = launchpad::get_launchpad_info(dao_addr);
        assert!(is_active == true, EASSERTION_FAILED);

        // Emergency pause
        launchpad::emergency_pause(admin, dao_addr);
        let (_, _, _, _, _, is_active_paused) = launchpad::get_launchpad_info(dao_addr);
        assert!(is_active_paused == false, EASSERTION_FAILED + 1);

        // Emergency resume
        launchpad::emergency_resume(admin, dao_addr);
        let (_, _, _, _, _, is_active_resumed) = launchpad::get_launchpad_info(dao_addr);
        assert!(is_active_resumed == true, EASSERTION_FAILED + 2);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, investor1 = @0x456)]
    #[expected_failure(abort_code = 5)] // ENOT_WHITELISTED
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
        let dao_addr = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_addr, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, false
        );

        // Setup timeline for presale
        let now = timestamp::now_seconds();
        launchpad::update_timeline(admin, dao_addr, now + 100, now + 150, now + 1000, now + 2000, now + 3000);

        // Advance time to reach whitelist start
        timestamp::fast_forward_seconds(150);
        
        // Advance to whitelist phase first
        launchpad::advance_phase(admin, dao_addr);
        
        // Advance time to reach presale start
        timestamp::fast_forward_seconds(1000);
        
        // Advance to presale phase
        launchpad::advance_phase(admin, dao_addr);

        // Try to purchase without being whitelisted - should fail
        launchpad::purchase_tokens(investor1, dao_addr, 1000);

        test_utils::destroy_caps(aptos_framework);
    }

    #[test(aptos_framework = @0x1, admin = @0x123, investor1 = @0x456)]
    #[expected_failure(abort_code = 6)] // EEXCEEDS_ALLOCATION
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
        let dao_addr = signer::address_of(admin);

        dao_core::create_dao_launchpad(
            admin, dao_addr, string::utf8(b"Test Launch"), string::utf8(b"TEST"),
            1000000, 100, 30, 20, 6, 24, false
        );

        // Setup whitelist with small allocation
        let participants = vector::singleton(TEST_INVESTOR1);
        let tiers = vector::singleton(launchpad::tier_bronze());
        let allocations = vector::singleton(1000u64); // Only 1000 tokens allowed
        
        dao_core::manage_launchpad_whitelist(admin, dao_addr, participants, tiers, allocations);

        // Setup timeline for presale
        let now = timestamp::now_seconds();
        launchpad::update_timeline(admin, dao_addr, now + 100, now + 150, now + 1000, now + 2000, now + 3000);

        // Advance time to reach whitelist start
        timestamp::fast_forward_seconds(150);
        
        // Advance to whitelist phase first
        launchpad::advance_phase(admin, dao_addr);
        
        // Advance time to reach presale start
        timestamp::fast_forward_seconds(1000);
        
        // Advance to presale phase
        launchpad::advance_phase(admin, dao_addr);

        // Try to purchase more than allocation - should fail
        launchpad::purchase_tokens(investor1, dao_addr, 2000);

        test_utils::destroy_caps(aptos_framework);
    }
}