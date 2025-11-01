// Token launchpad - allows DAOs to create and sell their own tokens with vesting and whitelist features
module movedaoaddrx::launchpad {
    use std::signer;
    use std::vector;
    use std::string::String;
    use std::simple_map::{Self, SimpleMap};
    use std::event;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use movedaoaddrx::admin;
    use movedaoaddrx::errors;
    use movedaoaddrx::safe_math;
    use movedaoaddrx::time_security;
    use movedaoaddrx::input_validation;


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
        movedaoaddrx: address,
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
        movedaoaddrx: address,
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
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(admin)), errors::not_admin());
        assert!(!exists<LaunchpadConfig>(movedaoaddrx), errors::launchpad_exists());
        
        // Comprehensive input validation
        assert!(total_supply > 0, errors::invalid_amount());
        assert!(price_per_token > 0, errors::invalid_amount());
        assert!(presale_allocation_percent <= 100, errors::invalid_allocation());
        assert!(team_allocation_percent <= 100, errors::invalid_allocation());
        assert!(presale_allocation_percent + team_allocation_percent <= 80, errors::invalid_allocation()); // Leave at least 20% for public
        assert!(presale_allocation_percent + team_allocation_percent >= 10, errors::invalid_allocation()); // Ensure minimum allocations
        assert!(vesting_cliff_months <= 36, errors::invalid_time()); // Max 3 years cliff
        assert!(vesting_duration_months <= 120, errors::invalid_time()); // Max 10 years vesting
        assert!(vesting_duration_months >= vesting_cliff_months, errors::invalid_time()); // Duration must be >= cliff

        let now = timestamp::now_seconds();
        
        // Calculate allocations using safe math operations
        let presale_allocation = safe_math::safe_percentage(total_supply, presale_allocation_percent);
        let team_allocation = safe_math::safe_percentage(total_supply, team_allocation_percent);
        
        // Safe addition and subtraction for public allocation
        let total_allocated = safe_math::safe_add(presale_allocation, team_allocation);
        assert!(total_supply >= total_allocated, errors::invalid_allocation());
        let public_allocation = safe_math::safe_sub(total_supply, total_allocated);

        let config = LaunchpadConfig {
            project_name: copy project_name,
            token_name,
            total_supply,
            price_per_token,
            
            // Initially set all times to future (admin will update) - using safe math
            whitelist_start: safe_math::safe_add(now, 86400),     // 1 day from now
            presale_start: safe_math::safe_add(now, safe_math::safe_mul(86400, 7)),   // 1 week
            public_sale_start: safe_math::safe_add(now, safe_math::safe_mul(86400, 14)), // 2 weeks
            sale_end: safe_math::safe_add(now, safe_math::safe_mul(86400, 21)),       // 3 weeks
            
            presale_allocation,
            public_allocation,
            team_allocation,
            
            vesting_start: safe_math::safe_add(now, safe_math::safe_mul(86400, 30)),  // 1 month after creation
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
            movedaoaddrx,
            project_name,
            total_supply,
            created_at: now,
        });
    }

    // Update launch timeline with enhanced timestamp security
    public entry fun update_timeline(
        admin: &signer,
        movedaoaddrx: address,
        whitelist_start: u64,
        presale_start: u64,
        public_sale_start: u64,
        sale_end: u64,
        vesting_start: u64
    ) acquires LaunchpadConfig {
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(admin)), errors::not_admin());
        
        let config = borrow_global_mut<LaunchpadConfig>(movedaoaddrx);
        
        // Enhanced timestamp security validation
        let times = vector::empty<u64>();
        vector::push_back(&mut times, whitelist_start);
        vector::push_back(&mut times, presale_start);
        vector::push_back(&mut times, public_sale_start);
        vector::push_back(&mut times, sale_end);
        vector::push_back(&mut times, vesting_start);
        
        // Validate chronological order
        time_security::validate_chronological_order(&times);
        
        // Validate individual periods
        time_security::validate_time_period(presale_start, public_sale_start, 86400, 2592000); // 1 day to 30 days
        time_security::validate_time_period(public_sale_start, sale_end, 86400, 2592000);      // 1 day to 30 days
        time_security::validate_vesting_period(vesting_start, safe_math::safe_add(vesting_start, 31536000)); // 1 year vesting
        
        // Ensure reasonable future times (not too far ahead)
        let now = timestamp::now_seconds();
        assert!(whitelist_start >= now, errors::invalid_time());
        assert!(whitelist_start <= safe_math::safe_add(now, 7776000), errors::invalid_time()); // Max 90 days ahead
        
        config.whitelist_start = whitelist_start;
        config.presale_start = presale_start;
        config.public_sale_start = public_sale_start;
        config.sale_end = sale_end;
        config.vesting_start = vesting_start;
    }

    // Add participants to whitelist with gas optimization
    public entry fun add_to_whitelist(
        admin: &signer,
        movedaoaddrx: address,
        participants: vector<address>,
        tiers: vector<u8>,
        max_allocations: vector<u64>
    ) acquires Whitelist {
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(admin)), errors::not_admin());
        
        let len = vector::length(&participants);
        assert!(len == vector::length(&tiers), errors::invalid_allocation());
        assert!(len == vector::length(&max_allocations), errors::invalid_allocation());
        
        // Gas optimization: limit batch size to prevent gas limit issues
        assert!(len <= 50, errors::invalid_amount()); // Max 50 addresses per batch
        
        // Input validation using the validation module
        input_validation::validate_address_list(&participants, 50);
        
        let whitelist = borrow_global_mut<Whitelist>(movedaoaddrx);
        let now = timestamp::now_seconds();
        let i = 0;
        
        // Pre-validate all inputs before any state changes for gas efficiency
        while (i < len) {
            let participant = *vector::borrow(&participants, i);
            let tier = *vector::borrow(&tiers, i);
            
            assert!(!simple_map::contains_key(&whitelist.entries, &participant), errors::already_whitelisted());
            input_validation::validate_tier(tier);
            i = i + 1;
        };
        
        // Now perform all state changes
        i = 0;
        while (i < len) {
            let participant = *vector::borrow(&participants, i);
            let tier = *vector::borrow(&tiers, i);
            let max_allocation = *vector::borrow(&max_allocations, i);
            
            let entry = WhitelistEntry {
                participant,
                tier,
                max_allocation,
                kyc_verified: false,
                added_at: now,
            };
            
            simple_map::add(&mut whitelist.entries, participant, entry);
            whitelist.total_whitelisted = safe_math::safe_add(whitelist.total_whitelisted, 1);
            
            event::emit(WhitelistAdded {
                participant,
                tier,
                max_allocation,
                added_at: now,
            });
            
            i = i + 1;
        };
    }

    // Gas-optimized function for adding single participant
    public entry fun add_single_to_whitelist(
        admin: &signer,
        movedaoaddrx: address,
        participant: address,
        tier: u8,
        max_allocation: u64
    ) acquires Whitelist {
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(admin)), errors::not_admin());
        
        let whitelist = borrow_global_mut<Whitelist>(movedaoaddrx);
        assert!(!simple_map::contains_key(&whitelist.entries, &participant), errors::already_whitelisted());
        
        input_validation::validate_tier(tier);
        
        let now = timestamp::now_seconds();
        let entry = WhitelistEntry {
            participant,
            tier,
            max_allocation,
            kyc_verified: false,
            added_at: now,
        };
        
        simple_map::add(&mut whitelist.entries, participant, entry);
        whitelist.total_whitelisted = safe_math::safe_add(whitelist.total_whitelisted, 1);
        
        event::emit(WhitelistAdded {
            participant,
            tier,
            max_allocation,
            added_at: now,
        });
    }

    // Update KYC status
    public entry fun update_kyc_status(
        admin: &signer,
        movedaoaddrx: address,
        participant: address,
        verified: bool
    ) acquires Whitelist {
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(admin)), errors::not_admin());
        
        let whitelist = borrow_global_mut<Whitelist>(movedaoaddrx);
        assert!(simple_map::contains_key(&whitelist.entries, &participant), errors::not_whitelisted());
        
        let entry = simple_map::borrow_mut(&mut whitelist.entries, &participant);
        entry.kyc_verified = verified;
    }

    // Advance to next phase - ANYONE can call this to prevent admin manipulation
    public entry fun advance_phase(
        _caller: &signer,
        movedaoaddrx: address
    ) acquires LaunchpadConfig {
        let config = borrow_global_mut<LaunchpadConfig>(movedaoaddrx);
        let now = timestamp::now_seconds();
        let old_phase = config.current_phase;
        
        // Automatic phase progression based on timestamps - no admin gatekeeping
        if (config.current_phase == PHASE_SETUP && now >= config.whitelist_start) {
            config.current_phase = PHASE_WHITELIST;
        } else if (config.current_phase == PHASE_WHITELIST && now >= config.presale_start) {
            config.current_phase = PHASE_PRESALE;
        } else if (config.current_phase == PHASE_PRESALE && now >= config.public_sale_start) {
            config.current_phase = PHASE_PUBLIC_SALE;
        } else if ((config.current_phase == PHASE_PUBLIC_SALE || config.current_phase == PHASE_PRESALE) && now >= config.sale_end) {
            config.current_phase = PHASE_ENDED;
        } else {
            // No phase change is needed at this time
            return
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
        movedaoaddrx: address,
        token_amount: u64
    ) acquires LaunchpadConfig, Whitelist, PurchaseHistory, TokenReserve {
        let buyer_addr = signer::address_of(buyer);
        let config = borrow_global_mut<LaunchpadConfig>(movedaoaddrx);
        let now = timestamp::now_seconds();
        
        // Auto-advance phases if needed to prevent manipulation
        if (config.current_phase == PHASE_SETUP && now >= config.whitelist_start) {
            config.current_phase = PHASE_WHITELIST;
        } else if (config.current_phase == PHASE_WHITELIST && now >= config.presale_start) {
            config.current_phase = PHASE_PRESALE;
        } else if (config.current_phase == PHASE_PRESALE && now >= config.public_sale_start) {
            config.current_phase = PHASE_PUBLIC_SALE;
        } else if ((config.current_phase == PHASE_PUBLIC_SALE || config.current_phase == PHASE_PRESALE) && now >= config.sale_end) {
            config.current_phase = PHASE_ENDED;
        };
        
        // Check if sale is active
        assert!(config.is_active, errors::sale_not_active());
        assert!(config.current_phase == PHASE_PRESALE || config.current_phase == PHASE_PUBLIC_SALE, errors::sale_not_active());
        assert!(now < config.sale_end, errors::sale_ended());
        
        // Get buyer's tier and validate
        let (tier, max_allocation) = if (config.current_phase == PHASE_PRESALE) {
            let whitelist = borrow_global<Whitelist>(movedaoaddrx);
            assert!(simple_map::contains_key(&whitelist.entries, &buyer_addr), errors::not_whitelisted());
            
            let entry = simple_map::borrow(&whitelist.entries, &buyer_addr);
            if (config.kyc_required) {
                assert!(entry.kyc_verified, errors::not_whitelisted());
            };
            (entry.tier, entry.max_allocation)
        } else {
            (TIER_BRONZE, token_amount) // Public sale - no allocation limit
        };
        
        // Check allocation limits
        let purchase_history = borrow_global_mut<PurchaseHistory>(movedaoaddrx);
        let current_allocation = if (simple_map::contains_key(&purchase_history.buyer_allocations, &buyer_addr)) {
            *simple_map::borrow(&purchase_history.buyer_allocations, &buyer_addr)
        } else {
            0
        };
        
        if (config.current_phase == PHASE_PRESALE) {
            assert!(current_allocation + token_amount <= max_allocation, errors::exceeds_allocation());
        };
        
        // Calculate payment required with safe math to prevent overflow attacks
        assert!(config.price_per_token > 0, errors::invalid_amount());
        let payment_required = safe_math::safe_mul(token_amount, config.price_per_token);
        
        // Check token availability
        let token_reserve = borrow_global_mut<TokenReserve>(movedaoaddrx);
        if (config.current_phase == PHASE_PRESALE) {
            assert!(token_amount <= token_reserve.reserved_for_presale, errors::insufficient_tokens());
            token_reserve.reserved_for_presale = token_reserve.reserved_for_presale - token_amount;
        } else {
            assert!(token_amount <= token_reserve.reserved_for_public, errors::insufficient_tokens());
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
        purchase_history.total_purchases = safe_math::safe_add(purchase_history.total_purchases, 1);
        
        if (simple_map::contains_key(&purchase_history.buyer_allocations, &buyer_addr)) {
            let allocation = simple_map::borrow_mut(&mut purchase_history.buyer_allocations, &buyer_addr);
            *allocation = safe_math::safe_add(*allocation, token_amount);
        } else {
            simple_map::add(&mut purchase_history.buyer_allocations, buyer_addr, token_amount);
        };
        
        // Update config with safe math for overflow protection
        config.tokens_sold = safe_math::safe_add(config.tokens_sold, token_amount);
        config.funds_raised = safe_math::safe_add(config.funds_raised, payment_required);
        token_reserve.available_tokens = safe_math::safe_sub(token_reserve.available_tokens, token_amount);
        
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
        movedaoaddrx: address,
        beneficiary: address,
        amount: u64,
        cliff_duration: u64,
        vesting_duration: u64
    ) acquires VestingStorage, TokenReserve {
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(admin)), errors::not_admin());
        
        let vesting_storage = borrow_global_mut<VestingStorage>(movedaoaddrx);
        let token_reserve = borrow_global_mut<TokenReserve>(movedaoaddrx);
        let now = timestamp::now_seconds();
        
        assert!(!simple_map::contains_key(&vesting_storage.schedules, &beneficiary), errors::already_whitelisted());
        assert!(amount <= token_reserve.reserved_for_team, errors::insufficient_tokens());
        
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
        movedaoaddrx: address
    ) acquires VestingStorage {
        let beneficiary_addr = signer::address_of(beneficiary);
        let vesting_storage = borrow_global_mut<VestingStorage>(movedaoaddrx);
        let now = timestamp::now_seconds();
        
        assert!(simple_map::contains_key(&vesting_storage.schedules, &beneficiary_addr), errors::vesting_not_started());
        
        let schedule = simple_map::borrow_mut(&mut vesting_storage.schedules, &beneficiary_addr);
        let claimable = calculate_claimable_amount(schedule, now);
        
        assert!(claimable > 0, errors::no_tokens_to_claim());
        
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
        
        // Calculate proportional vesting with proper overflow protection
        assert!(schedule.vesting_duration > 0, errors::invalid_amount());
        assert!(schedule.total_amount <= (18446744073709551615u64 / elapsed_time), errors::invalid_amount());
        let vested_amount = (schedule.total_amount * elapsed_time) / schedule.vesting_duration;
        if (vested_amount > schedule.claimed_amount) {
            vested_amount - schedule.claimed_amount
        } else {
            0
        }
    }

    // View functions
    #[view]
    public fun get_launchpad_info(movedaoaddrx: address): (String, String, u64, u64, u8, bool) acquires LaunchpadConfig {
        let config = borrow_global<LaunchpadConfig>(movedaoaddrx);
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
    public fun get_sale_stats(movedaoaddrx: address): (u64, u64, u64, u64) acquires LaunchpadConfig {
        let config = borrow_global<LaunchpadConfig>(movedaoaddrx);
        let total_allocation = config.presale_allocation + config.public_allocation;
        let percentage_sold = if (total_allocation > 0) {
            (config.tokens_sold * 100) / total_allocation
        } else {
            0
        };
        (
            config.tokens_sold,
            config.funds_raised,
            total_allocation,
            percentage_sold
        )
    }

    #[view]
    public fun is_whitelisted(movedaoaddrx: address, participant: address): bool acquires Whitelist {
        if (!exists<Whitelist>(movedaoaddrx)) return false;
        let whitelist = borrow_global<Whitelist>(movedaoaddrx);
        simple_map::contains_key(&whitelist.entries, &participant)
    }

    #[view]
    public fun get_whitelist_info(movedaoaddrx: address, participant: address): (u8, u64, bool) acquires Whitelist {
        let whitelist = borrow_global<Whitelist>(movedaoaddrx);
        assert!(simple_map::contains_key(&whitelist.entries, &participant), errors::not_whitelisted());
        
        let entry = simple_map::borrow(&whitelist.entries, &participant);
        (entry.tier, entry.max_allocation, entry.kyc_verified)
    }

    #[view]
    public fun get_purchase_history(movedaoaddrx: address, buyer: address): u64 acquires PurchaseHistory {
        if (!exists<PurchaseHistory>(movedaoaddrx)) return 0;
        let history = borrow_global<PurchaseHistory>(movedaoaddrx);
        if (simple_map::contains_key(&history.buyer_allocations, &buyer)) {
            *simple_map::borrow(&history.buyer_allocations, &buyer)
        } else {
            0
        }
    }

    #[view]
    public fun get_vesting_info(movedaoaddrx: address, beneficiary: address): (u64, u64, u64) acquires VestingStorage {
        let vesting_storage = borrow_global<VestingStorage>(movedaoaddrx);
        if (!simple_map::contains_key(&vesting_storage.schedules, &beneficiary)) {
            return (0, 0, 0)
        };
        
        let schedule = simple_map::borrow(&vesting_storage.schedules, &beneficiary);
        let now = timestamp::now_seconds();
        let claimable = calculate_claimable_amount(schedule, now);
        
        (schedule.total_amount, schedule.claimed_amount, claimable)
    }

    #[view]
    public fun get_timeline(movedaoaddrx: address): (u64, u64, u64, u64, u64) acquires LaunchpadConfig {
        let config = borrow_global<LaunchpadConfig>(movedaoaddrx);
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
        movedaoaddrx: address
    ) acquires LaunchpadConfig {
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(admin)), errors::not_admin());
        let config = borrow_global_mut<LaunchpadConfig>(movedaoaddrx);
        config.is_active = false;
    }

    public entry fun emergency_resume(
        admin: &signer,
        movedaoaddrx: address
    ) acquires LaunchpadConfig {
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(admin)), errors::not_admin());
        let config = borrow_global_mut<LaunchpadConfig>(movedaoaddrx);
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