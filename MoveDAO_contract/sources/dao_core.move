// Main DAO factory - creates and manages DAOs with their core components (treasury, council, membership)
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
        subname: string::String,
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
        subname: string::String,
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

    #[event]
    struct DAOCreationProposal has drop, store {
        proposal_id: u64,
        proposing_council: address,
        proposer: address,
        target_dao_address: address,
        name: string::String,
        subname: string::String,
        description: string::String,
        created_at: u64
    }

    #[event]
    struct CouncilDAOCreated has drop, store {
        dao_address: address,
        creating_council: address,
        proposal_id: u64,
        name: string::String,
        subname: string::String,
        description: string::String,
        created_at: u64,
        yes_votes: u64,
        total_council_size: u64
    }

    struct DAOCreationProposalData has store {
        id: u64,
        proposer: address,
        target_dao_address: address,
        name: string::String,
        subname: string::String,
        description: string::String,
        logo: vector<u8>,
        background: vector<u8>,
        initial_council: vector<address>,
        min_stake_to_join: u64,
        created_at: u64,
        voting_deadline: u64,
        yes_votes: u64,
        no_votes: u64,
        voted_members: vector<address>,
        executed: bool,
        approved: bool
    }

    struct CouncilDAOCreationRegistry has key {
        proposals: vector<DAOCreationProposalData>,
        next_proposal_id: u64,
        voting_duration: u64  // Duration in seconds for voting on DAO creation proposals
    }

    public entry fun create_dao(
        account: &signer,
        name: string::String,
        subname: string::String,
        description: string::String,
        logo: vector<u8>,
        background: vector<u8>,
        initial_council: vector<address>,
        min_stake_to_join: u64 // Now used for membership configuration
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
        
        // Validate minimum stake (should be reasonable - between 1 and 10000 APT)
        assert!(min_stake_to_join > 0, errors::invalid_amount());
        assert!(min_stake_to_join <= 10000, errors::invalid_amount());

        let council = council::init_council(account, initial_council, 1, 10);
        let treasury = treasury::init_treasury(account);
        let created_at = timestamp::now_seconds();

        move_to(account, DAOInfo {
            name,
            subname,
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
        proposal::initialize_proposals(account);
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
            subname,
            description,
            created_at,
            initial_council_size: vector::length(&initial_council)
        });
    }

    // Initialize council DAO creation registry for existing councils
    public entry fun init_council_dao_creation(council_account: &signer, voting_duration: u64) {
        let addr = signer::address_of(council_account);
        assert!(!exists<CouncilDAOCreationRegistry>(addr), error::already_exists(0));
        assert!(exists<DAOInfo>(addr), errors::not_found()); // Must be an existing DAO/council
        
        // Validate voting duration (minimum 1 hour, maximum 7 days)
        assert!(voting_duration >= 3600, errors::invalid_amount()); // 1 hour minimum
        assert!(voting_duration <= 604800, errors::invalid_amount()); // 7 days maximum
        
        let registry = CouncilDAOCreationRegistry {
            proposals: vector::empty(),
            next_proposal_id: 0,
            voting_duration
        };
        
        move_to(council_account, registry);
    }

    // Council members can propose new DAO creation
    public entry fun propose_dao_creation(
        council_member: &signer,
        council_dao_addr: address,
        target_dao_address: address,
        name: string::String,
        subname: string::String,
        description: string::String,
        logo: vector<u8>,
        background: vector<u8>,
        initial_council: vector<address>,
        min_stake_to_join: u64
    ) acquires DAOInfo, CouncilDAOCreationRegistry {
        let proposer = signer::address_of(council_member);
        
        // Verify proposer is a council member of the proposing DAO
        assert!(exists<DAOInfo>(council_dao_addr), errors::not_found());
        let dao_info = borrow_global<DAOInfo>(council_dao_addr);
        assert!(council::is_council_member_in_object(dao_info.council, proposer), errors::not_council_member());
        
        // Verify target DAO address doesn't already exist
        assert!(!exists<DAOInfo>(target_dao_address), error::already_exists(0));
        
        // Comprehensive input validation
        input_validation::validate_dao_name(&name);
        input_validation::validate_dao_description(&description);
        input_validation::validate_logo(&logo);
        input_validation::validate_background(&background);
        input_validation::validate_address_list(&initial_council, input_validation::get_max_council_size());
        input_validation::validate_council_size(vector::length(&initial_council));
        
        assert!(min_stake_to_join > 0, errors::invalid_amount());
        assert!(min_stake_to_join <= 10000, errors::invalid_amount());
        
        // Registry must be initialized first
        assert!(exists<CouncilDAOCreationRegistry>(council_dao_addr), errors::registry_not_initialized());
        
        let registry = borrow_global_mut<CouncilDAOCreationRegistry>(council_dao_addr);
        let proposal_id = registry.next_proposal_id;
        registry.next_proposal_id = proposal_id + 1;
        
        let created_at = timestamp::now_seconds();
        let voting_deadline = created_at + registry.voting_duration;
        
        let proposal = DAOCreationProposalData {
            id: proposal_id,
            proposer,
            target_dao_address,
            name,
            subname,
            description,
            logo,
            background,
            initial_council,
            min_stake_to_join,
            created_at,
            voting_deadline,
            yes_votes: 0,
            no_votes: 0,
            voted_members: vector::empty(),
            executed: false,
            approved: false
        };
        
        vector::push_back(&mut registry.proposals, proposal);
        
        // Emit proposal event
        event::emit(DAOCreationProposal {
            proposal_id,
            proposing_council: council_dao_addr,
            proposer,
            target_dao_address,
            name,
            subname,
            description,
            created_at
        });
    }

    // Council members vote on DAO creation proposals
    public entry fun vote_on_dao_creation(
        council_member: &signer,
        council_dao_addr: address,
        proposal_id: u64,
        approve: bool
    ) acquires DAOInfo, CouncilDAOCreationRegistry {
        let voter = signer::address_of(council_member);
        
        // Verify voter is a council member
        assert!(exists<DAOInfo>(council_dao_addr), errors::not_found());
        let dao_info = borrow_global<DAOInfo>(council_dao_addr);
        assert!(council::is_council_member_in_object(dao_info.council, voter), errors::not_council_member());
        
        let registry = borrow_global_mut<CouncilDAOCreationRegistry>(council_dao_addr);
        assert!(proposal_id < vector::length(&registry.proposals), errors::proposal_not_found());
        
        let proposal = vector::borrow_mut(&mut registry.proposals, proposal_id);
        assert!(!proposal.executed, errors::proposal_already_executed());
        assert!(timestamp::now_seconds() <= proposal.voting_deadline, errors::voting_period_ended());
        
        // Check if member has already voted
        let i = 0;
        let len = vector::length(&proposal.voted_members);
        let already_voted = false;
        while (i < len) {
            if (*vector::borrow(&proposal.voted_members, i) == voter) {
                already_voted = true;
                break
            };
            i = i + 1;
        };
        assert!(!already_voted, errors::already_voted());
        
        // Record vote
        vector::push_back(&mut proposal.voted_members, voter);
        if (approve) {
            proposal.yes_votes = proposal.yes_votes + 1;
        } else {
            proposal.no_votes = proposal.no_votes + 1;
        };
    }

    // Execute DAO creation if proposal passes
    public entry fun execute_dao_creation(
        executor: &signer,
        council_dao_addr: address,
        proposal_id: u64
    ) acquires DAOInfo, CouncilDAOCreationRegistry {
        let executor_addr = signer::address_of(executor);
        
        // Verify executor is a council member
        assert!(exists<DAOInfo>(council_dao_addr), errors::not_found());
        let dao_info = borrow_global<DAOInfo>(council_dao_addr);
        assert!(council::is_council_member_in_object(dao_info.council, executor_addr), errors::not_council_member());
        
        let registry = borrow_global_mut<CouncilDAOCreationRegistry>(council_dao_addr);
        assert!(proposal_id < vector::length(&registry.proposals), errors::proposal_not_found());
        
        let proposal = vector::borrow_mut(&mut registry.proposals, proposal_id);
        assert!(!proposal.executed, errors::proposal_already_executed());
        assert!(timestamp::now_seconds() > proposal.voting_deadline, errors::voting_period_active());
        
        // Check if proposal passes (simple majority)
        let total_council_size = council::get_member_count_from_object(dao_info.council);
        let required_votes = (total_council_size / 2) + 1; // Simple majority
        let passed = proposal.yes_votes >= required_votes;
        
        proposal.executed = true;
        proposal.approved = passed;
        
        if (passed) {
            // Create the target signer for the new DAO - this is a simplified approach
            // In production, you might want a more sophisticated DAO address generation mechanism
            assert!(!exists<DAOInfo>(proposal.target_dao_address), error::already_exists(0));
            
            // For now, we'll create a placeholder that needs to be properly initialized by the target address owner
            // This is a design limitation - the target address owner must call a separate initialization function
            // Alternative: Use object-based DAO creation for better address management
            
            event::emit(CouncilDAOCreated {
                dao_address: proposal.target_dao_address,
                creating_council: council_dao_addr,
                proposal_id,
                name: proposal.name,
                subname: proposal.subname,
                description: proposal.description,
                created_at: timestamp::now_seconds(),
                yes_votes: proposal.yes_votes,
                total_council_size
            });
        };
    }

    // Helper function for approved DAO creation by target address owner
    public entry fun finalize_council_created_dao(
        target_account: &signer,
        council_dao_addr: address,
        proposal_id: u64
    ) acquires CouncilDAOCreationRegistry {
        let addr = signer::address_of(target_account);
        
        let registry = borrow_global<CouncilDAOCreationRegistry>(council_dao_addr);
        assert!(proposal_id < vector::length(&registry.proposals), errors::proposal_not_found());
        
        let proposal = vector::borrow(&registry.proposals, proposal_id);
        assert!(proposal.target_dao_address == addr, errors::unauthorized());
        assert!(proposal.executed, errors::proposal_not_executed());
        assert!(proposal.approved, errors::proposal_not_approved());
        assert!(!exists<DAOInfo>(addr), error::already_exists(0));
        
        // Now create the actual DAO using the approved parameters
        let council = council::init_council(target_account, proposal.initial_council, 1, 10);
        let treasury = treasury::init_treasury(target_account);
        let created_at = timestamp::now_seconds();

        move_to(target_account, DAOInfo {
            name: proposal.name,
            subname: proposal.subname,
            description: proposal.description,
            logo: proposal.logo,
            background: proposal.background,
            created_at,
            council,
            treasury
        });

        // Initialize all required modules
        admin::init_admin(target_account, 1);
        membership::initialize_with_min_stake(target_account, proposal.min_stake_to_join);
        proposal::initialize_proposals(target_account);
        staking::init_staking(target_account);
        
        // Initialize rewards with default configuration
        rewards::initialize_rewards(
            target_account,
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
            name: proposal.name,
            subname: proposal.subname,
            description: proposal.description,
            created_at,
            initial_council_size: vector::length(&proposal.initial_council)
        });
    }

    // View functions for council DAO creation
    #[view]
    public fun get_dao_creation_proposal(
        council_dao_addr: address,
        proposal_id: u64
    ): (u64, address, address, string::String, string::String, u64, u64, u64, u64, bool, bool) acquires CouncilDAOCreationRegistry {
        assert!(exists<CouncilDAOCreationRegistry>(council_dao_addr), errors::registry_not_initialized());
        let registry = borrow_global<CouncilDAOCreationRegistry>(council_dao_addr);
        assert!(proposal_id < vector::length(&registry.proposals), errors::proposal_not_found());
        
        let proposal = vector::borrow(&registry.proposals, proposal_id);
        (
            proposal.id,
            proposal.proposer,
            proposal.target_dao_address,
            proposal.name,
            proposal.description,
            proposal.created_at,
            proposal.voting_deadline,
            proposal.yes_votes,
            proposal.no_votes,
            proposal.executed,
            proposal.approved
        )
    }

    #[view]
    public fun get_dao_creation_proposal_count(council_dao_addr: address): u64 acquires CouncilDAOCreationRegistry {
        if (!exists<CouncilDAOCreationRegistry>(council_dao_addr)) return 0;
        let registry = borrow_global<CouncilDAOCreationRegistry>(council_dao_addr);
        vector::length(&registry.proposals)
    }

    #[view]
    public fun has_voted_on_dao_creation(
        council_dao_addr: address,
        proposal_id: u64,
        voter: address
    ): bool acquires CouncilDAOCreationRegistry {
        if (!exists<CouncilDAOCreationRegistry>(council_dao_addr)) return false;
        let registry = borrow_global<CouncilDAOCreationRegistry>(council_dao_addr);
        if (proposal_id >= vector::length(&registry.proposals)) return false;
        
        let proposal = vector::borrow(&registry.proposals, proposal_id);
        let i = 0;
        let len = vector::length(&proposal.voted_members);
        while (i < len) {
            if (*vector::borrow(&proposal.voted_members, i) == voter) {
                return true
            };
            i = i + 1;
        };
        false
    }

    #[view]
    public fun is_dao_creation_registry_initialized(council_dao_addr: address): bool {
        exists<CouncilDAOCreationRegistry>(council_dao_addr)
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