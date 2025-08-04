module dao_addr::dao_core {
    use std::signer;
    use std::string;
    use std::error;
    use std::event;
    use std::vector;
    use aptos_framework::timestamp;
    use dao_addr::admin;
    use dao_addr::council;
    use dao_addr::membership;
    use dao_addr::proposal;
    use dao_addr::staking;
    use dao_addr::treasury;
    use dao_addr::rewards;
    use dao_addr::launchpad;
    use dao_addr::errors;
    use dao_addr::input_validation;
    use dao_addr::council::CouncilConfig;
    use dao_addr::treasury::Treasury;
    use aptos_framework::object::Object;

    struct DAOInfo has key {
        name: string::String,
        description: string::String,
        logo: vector<u8>,
        background: vector<u8>,
        created_at: u64,
        council: Object<CouncilConfig>,
        treasury: Object<Treasury>
    }

    #[event]
    struct DAOCreated has drop, store {
        dao_address: address,
        creator: address,
        name: string::String,
        description: string::String,
        created_at: u64,
        initial_council_size: u64
    }

    #[event]
    struct LaunchpadCreated has drop, store {
        dao_address: address,
        creator: address,
        project_name: string::String,
        token_name: string::String,
        total_supply: u64,
        price_per_token: u64,
        created_at: u64
    }

    public entry fun create_dao(
        account: &signer,
        name: string::String,
        description: string::String,
        logo: vector<u8>,
        background: vector<u8>,
        initial_council: vector<address>,
        min_stake_to_join: u64, // Now used for membership configuration
        min_voting_period: u64,
        max_voting_period: u64
    ) {
        let addr = signer::address_of(account);
        assert!(!exists<DAOInfo>(addr), error::already_exists(0));

        // Comprehensive input validation
        input_validation::validate_dao_name(&name);
        input_validation::validate_dao_description(&description);
        input_validation::validate_logo(&logo);
        input_validation::validate_background(&background);
        input_validation::validate_address_list(&initial_council, input_validation::get_max_council_size());
        input_validation::validate_council_size(vector::length(&initial_council));
        input_validation::validate_voting_period_bounds(min_voting_period, max_voting_period);
        
        // Validate minimum stake (should be reasonable - between 1 and 10000 APT)
        assert!(min_stake_to_join > 0, errors::invalid_amount());
        assert!(min_stake_to_join <= 10000, errors::invalid_amount());

        let council = council::init_council(account, initial_council, 1, 10);
        let treasury = treasury::init_treasury(account);
        let created_at = timestamp::now_seconds();

        move_to(account, DAOInfo {
            name,
            description,
            logo,
            background,
            created_at,
            council,
            treasury
        });

        // Initialize all required modules
        admin::init_admin(account, 1);
        membership::initialize_with_min_stake(account, min_stake_to_join);
        proposal::initialize_proposals(account, min_voting_period, max_voting_period);
        staking::init_staking(account);
        
        // Initialize rewards with default configuration
        rewards::initialize_rewards(
            account,
            10,      // voting_reward_per_vote: 10 tokens per vote
            100,     // proposal_creation_reward: 100 tokens per proposal
            500,     // successful_proposal_reward: 500 tokens for successful proposals
            500,     // staking_yield_rate: 5% annual (500 = 5.00%)
            86400    // staking_distribution_interval: daily (24 hours in seconds)
        );

        // Emit DAO creation event
        event::emit(DAOCreated {
            dao_address: addr,
            creator: addr,
            name,
            description,
            created_at,
            initial_council_size: vector::length(&initial_council)
        });
    }

    #[view]
    public fun get_dao_info(addr: address): (string::String, string::String, vector<u8>, vector<u8>, u64)
    acquires DAOInfo {
        let dao = borrow_global<DAOInfo>(addr);
        (
            dao.name,
            dao.description,
            dao.logo,
            dao.background,
            dao.created_at
        )
    }

    // Helper functions to get objects from DAOInfo
    public fun get_council_object(dao_addr: address): Object<CouncilConfig> acquires DAOInfo {
        borrow_global<DAOInfo>(dao_addr).council
    }

    public fun get_treasury_object(dao_addr: address): Object<Treasury> acquires DAOInfo {
        borrow_global<DAOInfo>(dao_addr).treasury
    }

    public entry fun claim_rewards(
        account: &signer,
        dao_addr: address
    ) acquires DAOInfo {
        let user_addr = signer::address_of(account);
        
        // Enhanced access control checks
        // 1. Verify DAO exists
        assert!(exists<DAOInfo>(dao_addr), errors::not_found());
        
        // 2. Verify user is a legitimate member/staker before checking rewards
        assert!(membership::is_member(dao_addr, user_addr), errors::not_member());
        
        // 3. Check if user has any claimable rewards before proceeding
        let total_claimable = rewards::get_total_claimable(dao_addr, user_addr);
        assert!(total_claimable > 0, errors::nothing_to_claim());
        
        // 4. Additional validation: check if rewards system is enabled
        assert!(rewards::is_rewards_enabled(dao_addr), errors::invalid_status());
        
        // 5. Process the claim and get the actual amount claimed
        let claimed_amount = rewards::claim_rewards_internal(dao_addr, user_addr);
        
        // Only proceed with treasury operations if there were actually rewards to claim
        if (claimed_amount > 0) {
            // 6. Get treasury object and validate it exists
            let treasury_obj = get_treasury_object(dao_addr);
            let treasury_balance = treasury::get_balance_from_object(treasury_obj);
            
            // 7. Enhanced treasury validation
            assert!(treasury_balance >= claimed_amount, errors::insufficient_treasury());
            assert!(claimed_amount <= total_claimable, errors::invalid_amount()); // Prevent over-claiming
            
            // 8. Final security check: re-verify membership before transfer
            assert!(membership::is_member(dao_addr, user_addr), errors::not_member());
            
            // 9. Transfer from treasury to user for rewards
            treasury::withdraw_rewards_from_object(user_addr, treasury_obj, claimed_amount);
        };
    }

    // Launchpad integration functions
    public entry fun create_dao_launchpad(
        admin: &signer,
        dao_addr: address,
        project_name: string::String,
        token_name: string::String,
        total_supply: u64,
        price_per_token: u64,
        presale_allocation_percent: u64,
        team_allocation_percent: u64,
        vesting_cliff_months: u64,
        vesting_duration_months: u64,
        kyc_required: bool
    ) {
        let creator = signer::address_of(admin);
        
        // Comprehensive input validation for launchpad
        input_validation::validate_dao_name(&project_name);
        input_validation::validate_dao_name(&token_name);
        input_validation::validate_token_supply(total_supply);
        input_validation::validate_token_price(price_per_token);
        input_validation::validate_percentage(presale_allocation_percent);
        input_validation::validate_percentage(team_allocation_percent);
        
        // Validate allocation percentages don't exceed reasonable limits
        let allocations = vector::empty<u64>();
        vector::push_back(&mut allocations, presale_allocation_percent);
        vector::push_back(&mut allocations, team_allocation_percent);
        input_validation::validate_allocation_percentages(&allocations, 80); // Max 80% allocated
        
        launchpad::create_launchpad(
            admin,
            dao_addr,
            project_name,
            token_name,
            total_supply,
            price_per_token,
            presale_allocation_percent,
            team_allocation_percent,
            vesting_cliff_months,
            vesting_duration_months,
            kyc_required
        );

        // Emit launchpad creation event
        event::emit(LaunchpadCreated {
            dao_address: dao_addr,
            creator,
            project_name,
            token_name,
            total_supply,
            price_per_token,
            created_at: timestamp::now_seconds()
        });
    }

    // Helper to check if DAO has a launchpad (would need to be implemented in launchpad module)
    public entry fun manage_launchpad_whitelist(
        admin: &signer,
        dao_addr: address,
        participants: vector<address>,
        tiers: vector<u8>,
        max_allocations: vector<u64>
    ) {
        launchpad::add_to_whitelist(admin, dao_addr, participants, tiers, max_allocations);
    }
}