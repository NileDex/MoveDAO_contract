module dao_addr::launchpad {
    use std::signer;
    use std::vector;
    use std::string::{Self, String};
    use std::simple_map::{Self, SimpleMap};
    use std::event;
    use std::option::{Self, Option};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self, Object};
    use dao_addr::admin;

    // Error codes
    const ENOT_ADMIN: u64 = 1;
    const ELAUNCHPAD_EXISTS: u64 = 2;
    const ELAUNCHPAD_NOT_FOUND: u64 = 3;
    const EINVALID_PHASE: u64 = 4;
    const ENOT_WHITELISTED: u64 = 5;
    const EEXCEEDS_ALLOCATION: u64 = 6;
    const EINSUFFICIENT_PAYMENT: u64 = 7;
    const ESALE_NOT_ACTIVE: u64 = 8;
    const EVESTING_NOT_STARTED: u64 = 9;
    const ENO_TOKENS_TO_CLAIM: u64 = 10;
    const EINSUFFICIENT_TOKENS: u64 = 11;
    const EINVALID_TIME: u64 = 12;
    const EALREADY_WHITELISTED: u64 = 13;
    const EINVALID_ALLOCATION: u64 = 14;
    const ESALE_ENDED: u64 = 15;

    // Launch phases
    const PHASE_SETUP: u8 = 0;
    const PHASE_WHITELIST: u8 = 1;
    const PHASE_PRESALE: u8 = 2;
    const PHASE_PUBLIC_SALE: u8 = 3;
    const PHASE_ENDED: u8 = 4;
    const PHASE_CANCELLED: u8 = 5;

    // Participant tiers
    const TIER_BRONZE: u8 = 1;
    const TIER_SILVER: u8 = 2;
    const TIER_GOLD: u8 = 3;
    const TIER_PLATINUM: u8 = 4;

    struct LaunchpadConfig has key {
        project_name: String,
        token_name: String,
        total_supply: u64,
        price_per_token: u64, // In APT (micro units)
        
        // Phase timings
        whitelist_start: u64,
        presale_start: u64,
        public_sale_start: u64,
        sale_end: u64,
        
        // Allocations (in tokens)
        presale_allocation: u64,
        public_allocation: u64,
        team_allocation: u64,
        
        // Vesting parameters
        vesting_start: u64,
        vesting_cliff_months: u64,
        vesting_duration_months: u64,
        
        // Current state
        current_phase: u8,
        tokens_sold: u64,
        funds_raised: u64,
        
        // Flags
        is_active: bool,
        kyc_required: bool,
    }

    struct WhitelistEntry has store, copy, drop {
        participant: address,
        tier: u8,
        max_allocation: u64, // Max tokens they can buy
        kyc_verified: bool,
        added_at: u64,
    }

    struct Whitelist has key {
        entries: SimpleMap<address, WhitelistEntry>,
        total_whitelisted: u64,
    }

    struct Purchase has store, copy, drop {
        buyer: address,
        amount_tokens: u64,
        amount_paid: u64,
        purchase_time: u64,
        tier: u8,
        phase: u8,
    }

    struct PurchaseHistory has key {
        purchases: vector<Purchase>,
        total_purchases: u64,
        buyer_allocations: SimpleMap<address, u64>, // Total tokens bought per buyer
    }

    struct VestingSchedule has store, copy, drop {
        beneficiary: address,
        total_amount: u64,
        claimed_amount: u64,
        start_time: u64,
        cliff_duration: u64,
        vesting_duration: u64,
        created_at: u64,
    }

    struct VestingStorage has key {
        schedules: SimpleMap<address, VestingSchedule>,
        total_vested: u64,
        total_claimed: u64,
    }

    struct TokenReserve has key {
        available_tokens: u64,
        reserved_for_presale: u64,
        reserved_for_public: u64,
        reserved_for_team: u64,
        funds_collected: Coin<AptosCoin>,
    }

    struct LockupConfig has store, copy, drop {
        tier: u8,
        lockup_duration: u64, // seconds
        release_percentage: u64, // percentage released immediately (0-10000 basis points)
    }

    struct LockupSettings has key {
        tier_lockups: vector<LockupConfig>,
        default_lockup: u64,
    }

    // Events
    #[event]
    struct LaunchpadCreated has drop, store {
        dao_addr: address,
        project_name: String,
        total_supply: u64,
        created_at: u64,
    }

    #[event]
    struct WhitelistAdded has drop, store {
        participant: address,
        tier: u8,
        max_allocation: u64,
        added_at: u64,
    }

    #[event]
    struct TokensPurchased has drop, store {
        buyer: address,
        amount_tokens: u64,
        amount_paid: u64,
        phase: u8,
        tier: u8,
        purchase_time: u64,
    }

    #[event]
    struct TokensClaimed has drop, store {
        beneficiary: address,
        amount: u64,
        claimed_at: u64,
    }

    #[event]
    struct PhaseChanged has drop, store {
        old_phase: u8,
        new_phase: u8,
        changed_at: u64,
    }

    #[event]
    struct VestingScheduleCreated has drop, store {
        beneficiary: address,
        total_amount: u64,
        start_time: u64,
        cliff_duration: u64,
        vesting_duration: u64,
    }

    // Initialize launchpad for a DAO
    public entry fun create_launchpad(
        admin: &signer,
        dao_addr: address,
        project_name: String,
        token_name: String,
        total_supply: u64,
        price_per_token: u64,
        presale_allocation_percent: u64, // 0-100
        team_allocation_percent: u64,   // 0-100
        vesting_cliff_months: u64,
        vesting_duration_months: u64,
        kyc_required: bool
    ) {
        assert!(admin::is_admin(dao_addr, signer::address_of(admin)), ENOT_ADMIN);
        assert!(!exists<LaunchpadConfig>(dao_addr), ELAUNCHPAD_EXISTS);
        assert!(presale_allocation_percent + team_allocation_percent <= 80, EINVALID_ALLOCATION); // Leave 20% for public

        let now = timestamp::now_seconds();
        let presale_allocation = (total_supply * presale_allocation_percent) / 100;
        let team_allocation = (total_supply * team_allocation_percent) / 100;
        let public_allocation = total_supply - presale_allocation - team_allocation;

        let config = LaunchpadConfig {
            project_name: copy project_name,
            token_name,
            total_supply,
            price_per_token,
            
            // Initially set all times to future (admin will update)
            whitelist_start: now + 86400,     // 1 day from now
            presale_start: now + 86400 * 7,   // 1 week
            public_sale_start: now + 86400 * 14, // 2 weeks
            sale_end: now + 86400 * 21,       // 3 weeks
            
            presale_allocation,
            public_allocation,
            team_allocation,
            
            vesting_start: now + 86400 * 30,  // 1 month after creation
            vesting_cliff_months,
            vesting_duration_months,
            
            current_phase: PHASE_SETUP,
            tokens_sold: 0,
            funds_raised: 0,
            
            is_active: true,
            kyc_required,
        };

        let whitelist = Whitelist {
            entries: simple_map::new(),
            total_whitelisted: 0,
        };

        let purchase_history = PurchaseHistory {
            purchases: vector::empty(),
            total_purchases: 0,
            buyer_allocations: simple_map::new(),
        };

        let vesting_storage = VestingStorage {
            schedules: simple_map::new(),
            total_vested: 0,
            total_claimed: 0,
        };

        let token_reserve = TokenReserve {
            available_tokens: total_supply,
            reserved_for_presale: presale_allocation,
            reserved_for_public: public_allocation,
            reserved_for_team: team_allocation,
            funds_collected: coin::zero<AptosCoin>(),
        };

        // Default lockup settings based on tiers
        let tier_lockups = vector::empty();
        vector::push_back(&mut tier_lockups, LockupConfig { tier: TIER_BRONZE, lockup_duration: 86400 * 30, release_percentage: 2000 }); // 30 days, 20% immediate
        vector::push_back(&mut tier_lockups, LockupConfig { tier: TIER_SILVER, lockup_duration: 86400 * 60, release_percentage: 3000 }); // 60 days, 30% immediate  
        vector::push_back(&mut tier_lockups, LockupConfig { tier: TIER_GOLD, lockup_duration: 86400 * 90, release_percentage: 4000 });   // 90 days, 40% immediate
        vector::push_back(&mut tier_lockups, LockupConfig { tier: TIER_PLATINUM, lockup_duration: 86400 * 120, release_percentage: 5000 }); // 120 days, 50% immediate

        let lockup_settings = LockupSettings {
            tier_lockups,
            default_lockup: 86400 * 30, // 30 days default
        };

        move_to(admin, config);
        move_to(admin, whitelist);
        move_to(admin, purchase_history);
        move_to(admin, vesting_storage);
        move_to(admin, token_reserve);
        move_to(admin, lockup_settings);

        event::emit(LaunchpadCreated {
            dao_addr,
            project_name,
            total_supply,
            created_at: now,
        });
    }

    // Update launch timeline
    public entry fun update_timeline(
        admin: &signer,
        dao_addr: address,
        whitelist_start: u64,
        presale_start: u64,
        public_sale_start: u64,
        sale_end: u64,
        vesting_start: u64
    ) acquires LaunchpadConfig {
        assert!(admin::is_admin(dao_addr, signer::address_of(admin)), ENOT_ADMIN);
        
        let config = borrow_global_mut<LaunchpadConfig>(dao_addr);
        let now = timestamp::now_seconds();
        
        // Validate timeline order
        assert!(whitelist_start > now, EINVALID_TIME);
        assert!(presale_start > whitelist_start, EINVALID_TIME);
        assert!(public_sale_start > presale_start, EINVALID_TIME);
        assert!(sale_end > public_sale_start, EINVALID_TIME);
        assert!(vesting_start >= sale_end, EINVALID_TIME);
        
        config.whitelist_start = whitelist_start;
        config.presale_start = presale_start;
        config.public_sale_start = public_sale_start;
        config.sale_end = sale_end;
        config.vesting_start = vesting_start;
    }

    // Add participants to whitelist
    public entry fun add_to_whitelist(
        admin: &signer,
        dao_addr: address,
        participants: vector<address>,
        tiers: vector<u8>,
        max_allocations: vector<u64>
    ) acquires Whitelist {
        assert!(admin::is_admin(dao_addr, signer::address_of(admin)), ENOT_ADMIN);
        assert!(vector::length(&participants) == vector::length(&tiers), EINVALID_ALLOCATION);
        assert!(vector::length(&participants) == vector::length(&max_allocations), EINVALID_ALLOCATION);
        
        let whitelist = borrow_global_mut<Whitelist>(dao_addr);
        let now = timestamp::now_seconds();
        let i = 0;
        let len = vector::length(&participants);
        
        while (i < len) {
            let participant = *vector::borrow(&participants, i);
            let tier = *vector::borrow(&tiers, i);
            let max_allocation = *vector::borrow(&max_allocations, i);
            
            assert!(!simple_map::contains_key(&whitelist.entries, &participant), EALREADY_WHITELISTED);
            assert!(tier >= TIER_BRONZE && tier <= TIER_PLATINUM, EINVALID_ALLOCATION);
            
            let entry = WhitelistEntry {
                participant,
                tier,
                max_allocation,
                kyc_verified: false,
                added_at: now,
            };
            
            simple_map::add(&mut whitelist.entries, participant, entry);
            whitelist.total_whitelisted = whitelist.total_whitelisted + 1;
            
            event::emit(WhitelistAdded {
                participant,
                tier,
                max_allocation,
                added_at: now,
            });
            
            i = i + 1;
        };
    }

    // Update KYC status
    public entry fun update_kyc_status(
        admin: &signer,
        dao_addr: address,
        participant: address,
        verified: bool
    ) acquires Whitelist {
        assert!(admin::is_admin(dao_addr, signer::address_of(admin)), ENOT_ADMIN);
        
        let whitelist = borrow_global_mut<Whitelist>(dao_addr);
        assert!(simple_map::contains_key(&whitelist.entries, &participant), ENOT_WHITELISTED);
        
        let entry = simple_map::borrow_mut(&mut whitelist.entries, &participant);
        entry.kyc_verified = verified;
    }

    // Advance to next phase
    public entry fun advance_phase(
        admin: &signer,
        dao_addr: address
    ) acquires LaunchpadConfig {
        assert!(admin::is_admin(dao_addr, signer::address_of(admin)), ENOT_ADMIN);
        
        let config = borrow_global_mut<LaunchpadConfig>(dao_addr);
        let now = timestamp::now_seconds();
        let old_phase = config.current_phase;
        
        if (config.current_phase == PHASE_SETUP && now >= config.whitelist_start) {
            config.current_phase = PHASE_WHITELIST;
        } else if (config.current_phase == PHASE_WHITELIST && now >= config.presale_start) {
            config.current_phase = PHASE_PRESALE;
        } else if (config.current_phase == PHASE_PRESALE && now >= config.public_sale_start) {
            config.current_phase = PHASE_PUBLIC_SALE;
        } else if ((config.current_phase == PHASE_PUBLIC_SALE || config.current_phase == PHASE_PRESALE) && now >= config.sale_end) {
            config.current_phase = PHASE_ENDED;
        } else {
            abort EINVALID_PHASE
        };
        
        event::emit(PhaseChanged {
            old_phase,
            new_phase: config.current_phase,
            changed_at: now,
        });
    }

    // Purchase tokens
    public entry fun purchase_tokens(
        buyer: &signer,
        dao_addr: address,
        token_amount: u64
    ) acquires LaunchpadConfig, Whitelist, PurchaseHistory, TokenReserve {
        let buyer_addr = signer::address_of(buyer);
        let config = borrow_global_mut<LaunchpadConfig>(dao_addr);
        let now = timestamp::now_seconds();
        
        // Check if sale is active
        assert!(config.is_active, ESALE_NOT_ACTIVE);
        assert!(config.current_phase == PHASE_PRESALE || config.current_phase == PHASE_PUBLIC_SALE, ESALE_NOT_ACTIVE);
        assert!(now < config.sale_end, ESALE_ENDED);
        
        // Get buyer's tier and validate
        let (tier, max_allocation) = if (config.current_phase == PHASE_PRESALE) {
            let whitelist = borrow_global<Whitelist>(dao_addr);
            assert!(simple_map::contains_key(&whitelist.entries, &buyer_addr), ENOT_WHITELISTED);
            
            let entry = simple_map::borrow(&whitelist.entries, &buyer_addr);
            if (config.kyc_required) {
                assert!(entry.kyc_verified, ENOT_WHITELISTED);
            };
            (entry.tier, entry.max_allocation)
        } else {
            (TIER_BRONZE, token_amount) // Public sale - no allocation limit
        };
        
        // Check allocation limits
        let purchase_history = borrow_global_mut<PurchaseHistory>(dao_addr);
        let current_allocation = if (simple_map::contains_key(&purchase_history.buyer_allocations, &buyer_addr)) {
            *simple_map::borrow(&purchase_history.buyer_allocations, &buyer_addr)
        } else {
            0
        };
        
        if (config.current_phase == PHASE_PRESALE) {
            assert!(current_allocation + token_amount <= max_allocation, EEXCEEDS_ALLOCATION);
        };
        
        // Calculate payment required
        let payment_required = token_amount * config.price_per_token;
        
        // Check token availability
        let token_reserve = borrow_global_mut<TokenReserve>(dao_addr);
        if (config.current_phase == PHASE_PRESALE) {
            assert!(token_amount <= token_reserve.reserved_for_presale, EINSUFFICIENT_TOKENS);
            token_reserve.reserved_for_presale = token_reserve.reserved_for_presale - token_amount;
        } else {
            assert!(token_amount <= token_reserve.reserved_for_public, EINSUFFICIENT_TOKENS);
            token_reserve.reserved_for_public = token_reserve.reserved_for_public - token_amount;
        };
        
        // Process payment
        let payment = coin::withdraw<AptosCoin>(buyer, payment_required);
        coin::merge(&mut token_reserve.funds_collected, payment);
        
        // Update purchase records
        let purchase = Purchase {
            buyer: buyer_addr,
            amount_tokens: token_amount,
            amount_paid: payment_required,
            purchase_time: now,
            tier,
            phase: config.current_phase,
        };
        
        vector::push_back(&mut purchase_history.purchases, purchase);
        purchase_history.total_purchases = purchase_history.total_purchases + 1;
        
        if (simple_map::contains_key(&purchase_history.buyer_allocations, &buyer_addr)) {
            let allocation = simple_map::borrow_mut(&mut purchase_history.buyer_allocations, &buyer_addr);
            *allocation = *allocation + token_amount;
        } else {
            simple_map::add(&mut purchase_history.buyer_allocations, buyer_addr, token_amount);
        };
        
        // Update config
        config.tokens_sold = config.tokens_sold + token_amount;
        config.funds_raised = config.funds_raised + payment_required;
        token_reserve.available_tokens = token_reserve.available_tokens - token_amount;
        
        event::emit(TokensPurchased {
            buyer: buyer_addr,
            amount_tokens: token_amount,
            amount_paid: payment_required,
            phase: config.current_phase,
            tier,
            purchase_time: now,
        });
    }

    // Create vesting schedule for team/advisors
    public entry fun create_vesting_schedule(
        admin: &signer,
        dao_addr: address,
        beneficiary: address,
        amount: u64,
        cliff_duration: u64,
        vesting_duration: u64
    ) acquires VestingStorage, TokenReserve {
        assert!(admin::is_admin(dao_addr, signer::address_of(admin)), ENOT_ADMIN);
        
        let vesting_storage = borrow_global_mut<VestingStorage>(dao_addr);
        let token_reserve = borrow_global_mut<TokenReserve>(dao_addr);
        let now = timestamp::now_seconds();
        
        assert!(!simple_map::contains_key(&vesting_storage.schedules, &beneficiary), EALREADY_WHITELISTED);
        assert!(amount <= token_reserve.reserved_for_team, EINSUFFICIENT_TOKENS);
        
        let schedule = VestingSchedule {
            beneficiary,
            total_amount: amount,
            claimed_amount: 0,
            start_time: now,
            cliff_duration,
            vesting_duration,
            created_at: now,
        };
        
        simple_map::add(&mut vesting_storage.schedules, beneficiary, schedule);
        vesting_storage.total_vested = vesting_storage.total_vested + amount;
        token_reserve.reserved_for_team = token_reserve.reserved_for_team - amount;
        token_reserve.available_tokens = token_reserve.available_tokens - amount;
        
        event::emit(VestingScheduleCreated {
            beneficiary,
            total_amount: amount,
            start_time: now,
            cliff_duration,
            vesting_duration,
        });
    }

    // Claim vested tokens
    public entry fun claim_vested_tokens(
        beneficiary: &signer,
        dao_addr: address
    ) acquires VestingStorage {
        let beneficiary_addr = signer::address_of(beneficiary);
        let vesting_storage = borrow_global_mut<VestingStorage>(dao_addr);
        let now = timestamp::now_seconds();
        
        assert!(simple_map::contains_key(&vesting_storage.schedules, &beneficiary_addr), EVESTING_NOT_STARTED);
        
        let schedule = simple_map::borrow_mut(&mut vesting_storage.schedules, &beneficiary_addr);
        let claimable = calculate_claimable_amount(schedule, now);
        
        assert!(claimable > 0, ENO_TOKENS_TO_CLAIM);
        
        schedule.claimed_amount = schedule.claimed_amount + claimable;
        vesting_storage.total_claimed = vesting_storage.total_claimed + claimable;
        
        // In a real implementation, you would transfer actual tokens here
        // For now, we just emit an event
        event::emit(TokensClaimed {
            beneficiary: beneficiary_addr,
            amount: claimable,
            claimed_at: now,
        });
    }

    // Helper function to calculate claimable vested amount
    fun calculate_claimable_amount(schedule: &VestingSchedule, current_time: u64): u64 {
        if (current_time < schedule.start_time + schedule.cliff_duration) {
            return 0
        };
        
        let elapsed_time = current_time - schedule.start_time;
        if (elapsed_time >= schedule.vesting_duration) {
            // Fully vested
            return schedule.total_amount - schedule.claimed_amount
        };
        
        // Calculate proportional vesting
        let vested_amount = (schedule.total_amount * elapsed_time) / schedule.vesting_duration;
        if (vested_amount > schedule.claimed_amount) {
            vested_amount - schedule.claimed_amount
        } else {
            0
        }
    }

    // View functions
    #[view]
    public fun get_launchpad_info(dao_addr: address): (String, String, u64, u64, u8, bool) acquires LaunchpadConfig {
        let config = borrow_global<LaunchpadConfig>(dao_addr);
        (
            config.project_name,
            config.token_name,
            config.total_supply,
            config.price_per_token,
            config.current_phase,
            config.is_active
        )
    }

    #[view]
    public fun get_sale_stats(dao_addr: address): (u64, u64, u64, u64) acquires LaunchpadConfig {
        let config = borrow_global<LaunchpadConfig>(dao_addr);
        (
            config.tokens_sold,
            config.funds_raised,
            config.presale_allocation + config.public_allocation,
            config.tokens_sold * 100 / (config.presale_allocation + config.public_allocation)
        )
    }

    #[view]
    public fun is_whitelisted(dao_addr: address, participant: address): bool acquires Whitelist {
        if (!exists<Whitelist>(dao_addr)) return false;
        let whitelist = borrow_global<Whitelist>(dao_addr);
        simple_map::contains_key(&whitelist.entries, &participant)
    }

    #[view]
    public fun get_whitelist_info(dao_addr: address, participant: address): (u8, u64, bool) acquires Whitelist {
        let whitelist = borrow_global<Whitelist>(dao_addr);
        assert!(simple_map::contains_key(&whitelist.entries, &participant), ENOT_WHITELISTED);
        
        let entry = simple_map::borrow(&whitelist.entries, &participant);
        (entry.tier, entry.max_allocation, entry.kyc_verified)
    }

    #[view]
    public fun get_purchase_history(dao_addr: address, buyer: address): u64 acquires PurchaseHistory {
        if (!exists<PurchaseHistory>(dao_addr)) return 0;
        let history = borrow_global<PurchaseHistory>(dao_addr);
        if (simple_map::contains_key(&history.buyer_allocations, &buyer)) {
            *simple_map::borrow(&history.buyer_allocations, &buyer)
        } else {
            0
        }
    }

    #[view]
    public fun get_vesting_info(dao_addr: address, beneficiary: address): (u64, u64, u64) acquires VestingStorage {
        let vesting_storage = borrow_global<VestingStorage>(dao_addr);
        if (!simple_map::contains_key(&vesting_storage.schedules, &beneficiary)) {
            return (0, 0, 0)
        };
        
        let schedule = simple_map::borrow(&vesting_storage.schedules, &beneficiary);
        let now = timestamp::now_seconds();
        let claimable = calculate_claimable_amount(schedule, now);
        
        (schedule.total_amount, schedule.claimed_amount, claimable)
    }

    #[view]
    public fun get_timeline(dao_addr: address): (u64, u64, u64, u64, u64) acquires LaunchpadConfig {
        let config = borrow_global<LaunchpadConfig>(dao_addr);
        (
            config.whitelist_start,
            config.presale_start,
            config.public_sale_start,
            config.sale_end,
            config.vesting_start
        )
    }

    // Emergency functions
    public entry fun emergency_pause(
        admin: &signer,
        dao_addr: address
    ) acquires LaunchpadConfig {
        assert!(admin::is_admin(dao_addr, signer::address_of(admin)), ENOT_ADMIN);
        let config = borrow_global_mut<LaunchpadConfig>(dao_addr);
        config.is_active = false;
    }

    public entry fun emergency_resume(
        admin: &signer,
        dao_addr: address
    ) acquires LaunchpadConfig {
        assert!(admin::is_admin(dao_addr, signer::address_of(admin)), ENOT_ADMIN);
        let config = borrow_global_mut<LaunchpadConfig>(dao_addr);
        config.is_active = true;
    }

    // Constants for external use
    public fun phase_setup(): u8 { PHASE_SETUP }
    public fun phase_whitelist(): u8 { PHASE_WHITELIST }
    public fun phase_presale(): u8 { PHASE_PRESALE }
    public fun phase_public_sale(): u8 { PHASE_PUBLIC_SALE }
    public fun phase_ended(): u8 { PHASE_ENDED }
    
    public fun tier_bronze(): u8 { TIER_BRONZE }
    public fun tier_silver(): u8 { TIER_SILVER }
    public fun tier_gold(): u8 { TIER_GOLD }
    public fun tier_platinum(): u8 { TIER_PLATINUM }
}