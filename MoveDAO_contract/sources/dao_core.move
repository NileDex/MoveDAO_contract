// Main DAO factory - creates and manages DAOs with their core components (treasury, council, membership)
module movedaoaddrx::dao_core_file {
    use std::signer;
    use std::string;
    use std::error;
    use std::event;
    use std::vector;
    use aptos_framework::timestamp;
    #[test_only]
    use aptos_framework::account;
    use movedaoaddrx::admin;
    use movedaoaddrx::council;
    use movedaoaddrx::membership;
    use movedaoaddrx::proposal;
    use movedaoaddrx::staking;
    use movedaoaddrx::treasury;
    use movedaoaddrx::rewards;
    use movedaoaddrx::launchpad;
    use movedaoaddrx::errors;
    use movedaoaddrx::input_validation;
    use movedaoaddrx::activity_tracker;
    use movedaoaddrx::council::CouncilConfig;
    use movedaoaddrx::treasury::Treasury;
    use aptos_framework::object::Object;
    use aptos_std::simple_map::{Self, SimpleMap};

    // Image data can be either a URL or binary data
    struct ImageData has copy, drop, store {
        is_url: bool,              // true if it's a URL, false if it's binary data
        url: string::String,       // URL string (used when is_url = true)
        data: vector<u8>          // Binary data (used when is_url = false)
    }

    struct DAOInfo has key {
        name: string::String,
        subname: string::String,
        description: string::String,
        logo: ImageData,
        background: ImageData,
        created_at: u64,
        council: Object<CouncilConfig>,
        treasury: Object<Treasury>,
        initial_council: vector<address> // Store the original council members from creation
    }

    #[event]
    struct DAOCreated has drop, store {
        movedaoaddrxess: address,
        creator: address,
        name: string::String,
        subname: string::String,
        description: string::String,
        created_at: u64,
        initial_council_size: u64
    }

    #[event]
    struct LaunchpadCreated has drop, store {
        movedaoaddrxess: address,
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
        target_movedaoaddrxess: address,
        name: string::String,
        subname: string::String,
        description: string::String,
        created_at: u64
    }

    #[event]
    struct CouncilDAOCreated has drop, store {
        movedaoaddrxess: address,
        creating_council: address,
        proposal_id: u64,
        name: string::String,
        subname: string::String,
        description: string::String,
        created_at: u64,
        yes_votes: u64,
        total_council_size: u64
    }

    #[event]
    struct DAORegistered has drop, store {
        dao_address: address,
        registered_at: u64
    }

    struct DAOCreationProposalData has store {
        id: u64,
        proposer: address,
        target_movedaoaddrxess: address,
        name: string::String,
        subname: string::String,
        description: string::String,
        logo: ImageData,
        background: ImageData,
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

    struct DAOSummary has copy, drop, store {
        address: address,
        name: string::String,
        description: string::String,
        created_at: u64
    }

    struct DAORegistry has key {
        dao_addresses: vector<address>,
        total_daos: u64,
        created_at: u64
    }

    struct SubnameRegistry has key {
        used_subnames: SimpleMap<string::String, address>,
        total_subnames: u64
    }

    // Module initialization - automatically creates registry on deployment
    fun init_module(account: &signer) {
        // This function is called automatically when the module is first published
        // It initializes the global DAO registry at the module address
        move_to(account, DAORegistry {
            dao_addresses: vector::empty<address>(),
            total_daos: 0,
            created_at: timestamp::now_seconds()
        });
        
        // Initialize subname registry for unique subname tracking
        move_to(account, SubnameRegistry {
            used_subnames: simple_map::create<string::String, address>(),
            total_subnames: 0
        });

        // Initialize global activity tracker
        activity_tracker::initialize(account);
    }

    #[test_only]
    /// Initialize registry for test environment
    public fun init_registry_for_test() {
        let dao_module_signer = account::create_signer_for_test(@movedaoaddrx);
        if (!exists<DAORegistry>(@movedaoaddrx)) {
            move_to(&dao_module_signer, DAORegistry {
                dao_addresses: vector::empty(),
                total_daos: 0,
                created_at: timestamp::now_seconds()
            });
        };
        if (!exists<SubnameRegistry>(@movedaoaddrx)) {
            move_to(&dao_module_signer, SubnameRegistry {
                used_subnames: simple_map::create<string::String, address>(),
                total_subnames: 0
            });
        }
    }

    // Helper functions to create ImageData
    public fun create_image_from_url(url: string::String): ImageData {
        ImageData {
            is_url: true,
            url,
            data: vector::empty()
        }
    }

    public fun create_image_from_data(data: vector<u8>): ImageData {
        ImageData {
            is_url: false,
            url: string::utf8(b""),
            data
        }
    }

    // Helper functions to validate images
    fun validate_image_data(image: &ImageData) {
        if (image.is_url) {
            // Validate URL format and length
            input_validation::validate_image_url(&image.url);
        } else {
            // Validate binary data size
            input_validation::validate_logo(&image.data);
        }
    }

    fun validate_background_data(image: &ImageData) {
        if (image.is_url) {
            // Validate URL format and length
            input_validation::validate_image_url(&image.url);
        } else {
            // Validate binary data size
            input_validation::validate_background(&image.data);
        }
    }

    // Validate and reserve subname - ensures global uniqueness
    fun validate_and_reserve_subname(subname: &string::String, dao_address: address) acquires SubnameRegistry {
        // Ensure subname registry exists
        assert!(exists<SubnameRegistry>(@movedaoaddrx), errors::registry_not_initialized());
        
        let registry = borrow_global_mut<SubnameRegistry>(@movedaoaddrx);
        
        // Check if subname is already taken
        assert!(!simple_map::contains_key(&registry.used_subnames, subname), errors::subname_already_exists());
        
        // Reserve the subname
        simple_map::add(&mut registry.used_subnames, *subname, dao_address);
        registry.total_subnames = registry.total_subnames + 1;
    }

    // Check if subname is available (read-only)
    fun is_subname_available(subname: &string::String): bool acquires SubnameRegistry {
        if (!exists<SubnameRegistry>(@movedaoaddrx)) {
            return false
        };
        let registry = borrow_global<SubnameRegistry>(@movedaoaddrx);
        !simple_map::contains_key(&registry.used_subnames, subname)
    }

    // Legacy function - kept for backward compatibility but registry is now auto-initialized
    public entry fun init_dao_registry(admin: &signer) {
        // Registry is automatically initialized during module deployment
        // This function is kept for backward compatibility but does nothing
        let _addr = signer::address_of(admin);
        // Registry should already exist from module initialization
    }

    // Function to manually add an existing DAO to the registry (for retroactive registration)
    public entry fun add_dao_to_registry(admin: &signer, dao_address: address) acquires DAORegistry {
        let addr = signer::address_of(admin);
        assert!(addr == @movedaoaddrx, error::permission_denied(1)); // Only module admin can add
        assert!(exists<DAOInfo>(dao_address), errors::not_found()); // DAO must exist
        assert!(exists<DAORegistry>(@movedaoaddrx), errors::registry_not_initialized()); // Registry must exist
        
        let registry = borrow_global_mut<DAORegistry>(@movedaoaddrx);
        
        // Check if DAO is already in registry
        let i = 0;
        let len = vector::length(&registry.dao_addresses);
        while (i < len) {
            if (*vector::borrow(&registry.dao_addresses, i) == dao_address) {
                return // Already in registry
            };
            i = i + 1;
        };
        
        // Add to registry
        vector::push_back(&mut registry.dao_addresses, dao_address);
        registry.total_daos = registry.total_daos + 1;
    }

    fun ensure_registry_exists(_first_dao_creator: &signer) {
        // Registry is automatically initialized during module deployment via init_module
        // If it doesn't exist, something went wrong during deployment
        assert!(exists<DAORegistry>(@movedaoaddrx), errors::registry_not_initialized());
    }

    // Public function to check and initialize registry if needed
    // This can be called by anyone to ensure registry is set up
    public entry fun check_and_init_registry(admin: &signer) {
        let addr = signer::address_of(admin);
        // The registry should be stored at the module address for global access
        assert!(addr == @movedaoaddrx, error::permission_denied(1));
        
        // Don't fail if registry already exists, just return silently
        if (exists<DAORegistry>(addr)) {
            return
        };
        
        move_to(admin, DAORegistry {
            dao_addresses: vector::empty(),
            total_daos: 0,
            created_at: timestamp::now_seconds()
        });
    }

    fun add_to_registry(dao_addr: address) acquires DAORegistry {
        // Registry should already exist from module initialization
        assert!(exists<DAORegistry>(@movedaoaddrx), errors::registry_not_initialized());
        
        let registry = borrow_global_mut<DAORegistry>(@movedaoaddrx);
        
        // Check if already exists to avoid duplicates
        let i = 0;
        let len = vector::length(&registry.dao_addresses);
        let already_exists = false;
        while (i < len) {
            if (*vector::borrow(&registry.dao_addresses, i) == dao_addr) {
                already_exists = true;
                break
            };
            i = i + 1;
        };
        
        if (!already_exists) {
            vector::push_back(&mut registry.dao_addresses, dao_addr);
            registry.total_daos = registry.total_daos + 1;
        };
        
        // Always emit event for tracking
        event::emit(DAORegistered {
            dao_address: dao_addr,
            registered_at: timestamp::now_seconds()
        });
    }

    // Automatic registry initialization - creates registry at module address
    // Uses module init pattern for one-time setup
    fun init_registry_automatically() {
        // In Move, we cannot create signers for arbitrary addresses
        // But we can use the module initialization pattern
        // The registry will be initialized during module deployment
        // This is a placeholder - actual initialization happens in module init
    }

    // Create DAO with binary image data (backward compatibility)
    public entry fun create_dao(
        account: &signer,
        name: string::String,
        subname: string::String,
        description: string::String,
        logo: vector<u8>,
        background: vector<u8>,
        initial_council: vector<address>,
        min_stake_to_join: u64 // Now used for membership configuration
    ) acquires DAORegistry, SubnameRegistry {
        let logo_data = create_image_from_data(logo);
        let background_data = create_image_from_data(background);
        create_dao_internal(account, name, subname, description, logo_data, background_data, initial_council, min_stake_to_join);
    }

    // Create DAO with URL images
    public entry fun create_dao_with_urls(
        account: &signer,
        name: string::String,
        subname: string::String,
        description: string::String,
        logo_url: string::String,
        background_url: string::String,
        initial_council: vector<address>,
        min_stake_to_join: u64
    ) acquires DAORegistry, SubnameRegistry {
        let logo_data = create_image_from_url(logo_url);
        let background_data = create_image_from_url(background_url);
        create_dao_internal(account, name, subname, description, logo_data, background_data, initial_council, min_stake_to_join);
    }

    // Create DAO with mixed image types (URL + binary or vice versa)
    public entry fun create_dao_mixed(
        account: &signer,
        name: string::String,
        subname: string::String,
        description: string::String,
        logo_is_url: bool,
        logo_url: string::String,
        logo_data: vector<u8>,
        background_is_url: bool,
        background_url: string::String,
        background_data: vector<u8>,
        initial_council: vector<address>,
        min_stake_to_join: u64
    ) acquires DAORegistry, SubnameRegistry {
        let logo_image = if (logo_is_url) {
            create_image_from_url(logo_url)
        } else {
            create_image_from_data(logo_data)
        };
        
        let background_image = if (background_is_url) {
            create_image_from_url(background_url)
        } else {
            create_image_from_data(background_data)
        };
        
        create_dao_internal(account, name, subname, description, logo_image, background_image, initial_council, min_stake_to_join);
    }

    // Internal function to create DAO (used by all public create functions)
    fun create_dao_internal(
        account: &signer,
        name: string::String,
        subname: string::String,
        description: string::String,
        logo: ImageData,
        background: ImageData,
        initial_council: vector<address>,
        min_stake_to_join: u64
    ) acquires DAORegistry, SubnameRegistry {
        let addr = signer::address_of(account);
        // Allow multiple DAOs per address - comment out existence check
        // assert!(!exists<DAOInfo>(addr), error::already_exists(0));

        // Ensure DAO registry exists (auto-initialize if this is the first DAO)
        ensure_registry_exists(account);

        // Comprehensive input validation
        input_validation::validate_dao_name(&name);
        input_validation::validate_dao_name(&subname);
        input_validation::validate_dao_description(&description);
        validate_image_data(&logo);
        validate_background_data(&background);
        input_validation::validate_address_list(&initial_council, input_validation::get_max_council_size());
        input_validation::validate_council_size(vector::length(&initial_council));
        
        // Validate minimum stake (should be reasonable - between 6 and 10000 Move)
        assert!(min_stake_to_join >= 6000000, errors::invalid_amount()); // 6 Move minimum
        assert!(min_stake_to_join <= 10000000000, errors::invalid_amount()); // 10000 Move maximum

        // Validate and reserve subname for global uniqueness
        validate_and_reserve_subname(&subname, addr);

        let council = council::init_council(account, initial_council, 1, 10);
        let treasury = treasury::init_treasury(account);
        let created_at = timestamp::now_seconds();

        // Skip creation if DAO already exists from previous deployments
        // This allows new contract to work even with old DAO resources present
        if (!exists<DAOInfo>(addr)) {
            // Only create DAO if none exists (avoids conflict with old deployments)
            move_to(account, DAOInfo {
                name,
                subname,
                description,
                logo,
                background,
                created_at,
                council,
                treasury,
                initial_council
            });
        } else {
            // DAO already exists from previous deployment - skip creation but continue with setup
            // This prevents the "object already exists" error while allowing the transaction to succeed
        };

        // Initialize all required modules - check each one individually
        // Admin system
        if (!admin::exists_admin_list(addr)) {
            admin::init_admin(account, 1);
        };
        
        // Membership system
        if (!membership::is_membership_initialized(addr)) {
            membership::initialize_with_min_stake(account, min_stake_to_join);
        };
        
        // Proposal system
        if (!proposal::has_proposals(addr)) {
            proposal::initialize_proposals(account);
        };
        
        // Staking system
        if (!staking::is_staking_initialized(addr)) {
            staking::init_staking(account);
        };
        
        // Rewards system
        if (!rewards::is_rewards_initialized(addr)) {
            rewards::initialize_rewards(
                account,
                10,      // voting_reward_per_vote: 10 tokens per vote
                100,     // proposal_creation_reward: 100 tokens per proposal
                500,     // successful_proposal_reward: 500 tokens for successful proposals
                500,     // staking_yield_rate: 5% annual (500 = 5.00%)
                86400    // staking_distribution_interval: daily (24 hours in seconds)
            );
        };

        // Add to DAO registry
        add_to_registry(addr);

        // Log DAO creation activity
        activity_tracker::emit_dao_created(
            addr,                    // dao_address
            addr,                    // creator
            name,                    // name
            vector::empty<u8>(),     // transaction_hash (will be filled by the tracker)
            0                        // block_number (will be filled by the tracker)
        );

        // Emit DAO creation event
        event::emit(DAOCreated {
            movedaoaddrxess: addr,
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

    // Council members can propose new DAO creation (with binary data)
    public entry fun propose_dao_creation(
        council_member: &signer,
        council_movedaoaddrx: address,
        target_movedaoaddrxess: address,
        name: string::String,
        subname: string::String,
        description: string::String,
        logo: vector<u8>,
        background: vector<u8>,
        initial_council: vector<address>,
        min_stake_to_join: u64
    ) acquires DAOInfo, CouncilDAOCreationRegistry {
        let logo_data = create_image_from_data(logo);
        let background_data = create_image_from_data(background);
        propose_dao_creation_internal(council_member, council_movedaoaddrx, target_movedaoaddrxess, name, subname, description, logo_data, background_data, initial_council, min_stake_to_join);
    }

    // Council members can propose new DAO creation (with URLs)
    public entry fun propose_dao_creation_with_urls(
        council_member: &signer,
        council_movedaoaddrx: address,
        target_movedaoaddrxess: address,
        name: string::String,
        subname: string::String,
        description: string::String,
        logo_url: string::String,
        background_url: string::String,
        initial_council: vector<address>,
        min_stake_to_join: u64
    ) acquires DAOInfo, CouncilDAOCreationRegistry {
        let logo_data = create_image_from_url(logo_url);
        let background_data = create_image_from_url(background_url);
        propose_dao_creation_internal(council_member, council_movedaoaddrx, target_movedaoaddrxess, name, subname, description, logo_data, background_data, initial_council, min_stake_to_join);
    }

    // Internal function for DAO creation proposals
    fun propose_dao_creation_internal(
        council_member: &signer,
        council_movedaoaddrx: address,
        target_movedaoaddrxess: address,
        name: string::String,
        subname: string::String,
        description: string::String,
        logo: ImageData,
        background: ImageData,
        initial_council: vector<address>,
        min_stake_to_join: u64
    ) acquires DAOInfo, CouncilDAOCreationRegistry {
        let proposer = signer::address_of(council_member);
        
        // Verify proposer is a council member of the proposing DAO
        assert!(exists<DAOInfo>(council_movedaoaddrx), errors::not_found());
        let dao_info = borrow_global<DAOInfo>(council_movedaoaddrx);
        assert!(council::is_council_member_in_object(dao_info.council, proposer), errors::not_council_member());
        
        // Verify target DAO address doesn't already exist
        assert!(!exists<DAOInfo>(target_movedaoaddrxess), error::already_exists(0));
        
        // Comprehensive input validation
        input_validation::validate_dao_name(&name);
        input_validation::validate_dao_name(&subname);
        input_validation::validate_dao_description(&description);
        validate_image_data(&logo);
        validate_background_data(&background);
        input_validation::validate_address_list(&initial_council, input_validation::get_max_council_size());
        input_validation::validate_council_size(vector::length(&initial_council));
        
        assert!(min_stake_to_join >= 6000000, errors::invalid_amount()); // 6 Move minimum
        assert!(min_stake_to_join <= 10000000000, errors::invalid_amount()); // 10000 Move maximum
        
        // Registry must be initialized first
        assert!(exists<CouncilDAOCreationRegistry>(council_movedaoaddrx), errors::registry_not_initialized());
        
        let registry = borrow_global_mut<CouncilDAOCreationRegistry>(council_movedaoaddrx);
        let proposal_id = registry.next_proposal_id;
        registry.next_proposal_id = proposal_id + 1;
        
        let created_at = timestamp::now_seconds();
        let voting_deadline = created_at + registry.voting_duration;
        
        let proposal = DAOCreationProposalData {
            id: proposal_id,
            proposer,
            target_movedaoaddrxess,
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
            proposing_council: council_movedaoaddrx,
            proposer,
            target_movedaoaddrxess,
            name,
            subname,
            description,
            created_at
        });
    }

    // Council members vote on DAO creation proposals
    public entry fun vote_on_dao_creation(
        council_member: &signer,
        council_movedaoaddrx: address,
        proposal_id: u64,
        approve: bool
    ) acquires DAOInfo, CouncilDAOCreationRegistry {
        let voter = signer::address_of(council_member);
        
        // Verify voter is a council member
        assert!(exists<DAOInfo>(council_movedaoaddrx), errors::not_found());
        let dao_info = borrow_global<DAOInfo>(council_movedaoaddrx);
        assert!(council::is_council_member_in_object(dao_info.council, voter), errors::not_council_member());
        
        let registry = borrow_global_mut<CouncilDAOCreationRegistry>(council_movedaoaddrx);
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
        council_movedaoaddrx: address,
        proposal_id: u64
    ) acquires DAOInfo, CouncilDAOCreationRegistry {
        let executor_addr = signer::address_of(executor);
        
        // Verify executor is a council member
        assert!(exists<DAOInfo>(council_movedaoaddrx), errors::not_found());
        let dao_info = borrow_global<DAOInfo>(council_movedaoaddrx);
        assert!(council::is_council_member_in_object(dao_info.council, executor_addr), errors::not_council_member());
        
        let registry = borrow_global_mut<CouncilDAOCreationRegistry>(council_movedaoaddrx);
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
            assert!(!exists<DAOInfo>(proposal.target_movedaoaddrxess), error::already_exists(0));
            
            // For now, we'll create a placeholder that needs to be properly initialized by the target address owner
            // This is a design limitation - the target address owner must call a separate initialization function
            // Alternative: Use object-based DAO creation for better address management
            
            event::emit(CouncilDAOCreated {
                movedaoaddrxess: proposal.target_movedaoaddrxess,
                creating_council: council_movedaoaddrx,
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
        council_movedaoaddrx: address,
        proposal_id: u64
    ) acquires CouncilDAOCreationRegistry, DAORegistry {
        let addr = signer::address_of(target_account);
        
        let registry = borrow_global<CouncilDAOCreationRegistry>(council_movedaoaddrx);
        assert!(proposal_id < vector::length(&registry.proposals), errors::proposal_not_found());
        
        let proposal = vector::borrow(&registry.proposals, proposal_id);
        assert!(proposal.target_movedaoaddrxess == addr, errors::unauthorized());
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
            treasury,
            initial_council: proposal.initial_council
        });

        // Initialize all required modules - check each one individually
        // Admin system
        if (!admin::exists_admin_list(addr)) {
            admin::init_admin(target_account, 1);
        };
        
        // Membership system
        if (!membership::is_membership_initialized(addr)) {
            membership::initialize_with_min_stake(target_account, proposal.min_stake_to_join);
        };
        
        // Proposal system
        if (!proposal::has_proposals(addr)) {
            proposal::initialize_proposals(target_account);
        };
        
        // Staking system
        if (!staking::is_staking_initialized(addr)) {
            staking::init_staking(target_account);
        };
        
        // Rewards system
        if (!rewards::is_rewards_initialized(addr)) {
            rewards::initialize_rewards(
                target_account,
                10,      // voting_reward_per_vote: 10 tokens per vote
                100,     // proposal_creation_reward: 100 tokens per proposal
                500,     // successful_proposal_reward: 500 tokens for successful proposals
                500,     // staking_yield_rate: 5% annual (500 = 5.00%)
                86400    // staking_distribution_interval: daily (24 hours in seconds)
            );
        };

        // Add to DAO registry
        add_to_registry(addr);

        // Log DAO creation activity
        activity_tracker::emit_dao_created(
            addr,                    // dao_address
            addr,                    // creator
            proposal.name,           // name
            vector::empty<u8>(),     // transaction_hash (will be filled by the tracker)
            0                        // block_number (will be filled by the tracker)
        );

        // Emit DAO creation event
        event::emit(DAOCreated {
            movedaoaddrxess: addr,
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
        council_movedaoaddrx: address,
        proposal_id: u64
    ): (u64, address, address, string::String, string::String, u64, u64, u64, u64, bool, bool) acquires CouncilDAOCreationRegistry {
        assert!(exists<CouncilDAOCreationRegistry>(council_movedaoaddrx), errors::registry_not_initialized());
        let registry = borrow_global<CouncilDAOCreationRegistry>(council_movedaoaddrx);
        assert!(proposal_id < vector::length(&registry.proposals), errors::proposal_not_found());
        
        let proposal = vector::borrow(&registry.proposals, proposal_id);
        (
            proposal.id,
            proposal.proposer,
            proposal.target_movedaoaddrxess,
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
    public fun get_dao_creation_proposal_count(council_movedaoaddrx: address): u64 acquires CouncilDAOCreationRegistry {
        if (!exists<CouncilDAOCreationRegistry>(council_movedaoaddrx)) return 0;
        let registry = borrow_global<CouncilDAOCreationRegistry>(council_movedaoaddrx);
        vector::length(&registry.proposals)
    }

    #[view]
    public fun has_voted_on_dao_creation(
        council_movedaoaddrx: address,
        proposal_id: u64,
        voter: address
    ): bool acquires CouncilDAOCreationRegistry {
        if (!exists<CouncilDAOCreationRegistry>(council_movedaoaddrx)) return false;
        let registry = borrow_global<CouncilDAOCreationRegistry>(council_movedaoaddrx);
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
    public fun is_dao_creation_registry_initialized(council_movedaoaddrx: address): bool {
        exists<CouncilDAOCreationRegistry>(council_movedaoaddrx)
    }

    #[view]
    public fun get_dao_info(addr: address): (string::String, string::String, bool, string::String, vector<u8>, bool, string::String, vector<u8>, u64)
    acquires DAOInfo {
        let dao = borrow_global<DAOInfo>(addr);
        (
            dao.name,
            dao.description,
            dao.logo.is_url,
            dao.logo.url,
            dao.logo.data,
            dao.background.is_url,
            dao.background.url,
            dao.background.data,
            dao.created_at
        )
    }

    // New function with subname included
    #[view]
    public fun get_dao_info_with_subname(addr: address): (string::String, string::String, string::String, bool, string::String, vector<u8>, bool, string::String, vector<u8>, u64)
    acquires DAOInfo {
        let dao = borrow_global<DAOInfo>(addr);
        (
            dao.name,
            dao.subname,
            dao.description,
            dao.logo.is_url,
            dao.logo.url,
            dao.logo.data,
            dao.background.is_url,
            dao.background.url,
            dao.background.data,
            dao.created_at
        )
    }

    // Backward compatibility function (returns empty vectors for URLs)
    #[view]
    public fun get_dao_info_legacy(addr: address): (string::String, string::String, vector<u8>, vector<u8>, u64)
    acquires DAOInfo {
        let dao = borrow_global<DAOInfo>(addr);
        let logo_data = if (dao.logo.is_url) { vector::empty() } else { dao.logo.data };
        let background_data = if (dao.background.is_url) { vector::empty() } else { dao.background.data };
        (
            dao.name,
            dao.description,
            logo_data,
            background_data,
            dao.created_at
        )
    }

    // Helper functions to get objects from DAOInfo
    #[view]
    public fun get_council_object(movedaoaddrx: address): Object<CouncilConfig> acquires DAOInfo {
        borrow_global<DAOInfo>(movedaoaddrx).council
    }

    #[view]
    public fun get_treasury_object(movedaoaddrx: address): Object<Treasury> acquires DAOInfo {
        borrow_global<DAOInfo>(movedaoaddrx).treasury
    }

    // Check if a DAO exists (has DAOInfo resource)
    #[view]
    public fun dao_exists(movedaoaddrx: address): bool {
        exists<DAOInfo>(movedaoaddrx)
    }

    // Get council object for external use
    #[view]
    public fun get_council_info(movedaoaddrx: address): (Object<CouncilConfig>, u64) acquires DAOInfo {
        let dao_info = borrow_global<DAOInfo>(movedaoaddrx);
        let member_count = council::get_member_count_from_object(dao_info.council);
        (dao_info.council, member_count)
    }

    // Check if an address is a council member
    #[view]
    public fun is_council_member(movedaoaddrx: address, member: address): bool acquires DAOInfo {
        let dao_info = borrow_global<DAOInfo>(movedaoaddrx);
        council::is_council_member_in_object(dao_info.council, member)
    }

    // Get council member count
    #[view]
    public fun get_council_member_count(movedaoaddrx: address): u64 acquires DAOInfo {
        let dao_info = borrow_global<DAOInfo>(movedaoaddrx);
        council::get_member_count_from_object(dao_info.council)
    }

    // Get the initial council members that were set when DAO was created
    #[view]
    public fun get_initial_council(movedaoaddrx: address): vector<address> acquires DAOInfo {
        let dao_info = borrow_global<DAOInfo>(movedaoaddrx);
        dao_info.initial_council
    }


    // Get all DAO addresses from registry
    #[view]
    public fun get_all_dao_addresses(): vector<address> acquires DAORegistry {
        let registry = borrow_global<DAORegistry>(@movedaoaddrx);
        registry.dao_addresses
    }

    // Get all DAOs created by a specific address
    #[view]
    public fun get_daos_created_by(creator: address): vector<address> acquires DAORegistry {
        if (!exists<DAORegistry>(@movedaoaddrx)) {
            return vector::empty()
        };
        
        let registry = borrow_global<DAORegistry>(@movedaoaddrx);
        let dao_addresses = &registry.dao_addresses;
        let result = vector::empty<address>();
        
        let i = 0;
        let len = vector::length(dao_addresses);
        while (i < len) {
            let dao_addr = *vector::borrow(dao_addresses, i);
            // Check if this DAO was created by the specified address
            // In our system, DAOs are stored at the creator's address
            if (dao_addr == creator && exists<DAOInfo>(dao_addr)) {
                vector::push_back(&mut result, dao_addr);
            };
            i = i + 1;
        };
        
        result
    }

    // Get all DAOs that a specific address has joined as a member
    #[view]
    public fun get_daos_joined_by(member: address): vector<address> acquires DAORegistry {
        if (!exists<DAORegistry>(@movedaoaddrx)) {
            return vector::empty()
        };
        
        let registry = borrow_global<DAORegistry>(@movedaoaddrx);
        let dao_addresses = &registry.dao_addresses;
        let result = vector::empty<address>();
        
        let i = 0;
        let len = vector::length(dao_addresses);
        while (i < len) {
            let dao_addr = *vector::borrow(dao_addresses, i);
            // Check if the member is part of this DAO
            if (membership::is_member(dao_addr, member)) {
                vector::push_back(&mut result, dao_addr);
            };
            i = i + 1;
        };
        
        result
    }

    // Get both created and joined DAOs for a user (convenience function)
    #[view]
    public fun get_user_daos(user_address: address): (vector<address>, vector<address>) acquires DAORegistry {
        let created_daos = get_daos_created_by(user_address);
        let joined_daos = get_daos_joined_by(user_address);
        (created_daos, joined_daos)
    }

    // Helper function to check if DAO registry is working
    #[view] 
    public fun is_registry_functional(): bool {
        exists<DAORegistry>(@movedaoaddrx)
    }

    // Get total number of DAOs created
    #[view]
    public fun get_total_dao_count(): u64 acquires DAORegistry {
        let registry = borrow_global<DAORegistry>(@movedaoaddrx);
        registry.total_daos
    }

    // Check if registry is available (informational)
    #[view]
    public fun is_registry_initialized(): bool {
        exists<DAORegistry>(@movedaoaddrx)
    }

    // Get all DAOs with their basic info
    #[view]
    public fun get_all_daos(): vector<DAOSummary> acquires DAORegistry, DAOInfo {
        if (!exists<DAORegistry>(@movedaoaddrx)) {
            return vector::empty()
        };
        
        let registry = borrow_global<DAORegistry>(@movedaoaddrx);
        let dao_addresses = &registry.dao_addresses;
        let result = vector::empty<DAOSummary>();
        
        let i = 0;
        let len = vector::length(dao_addresses);
        while (i < len) {
            let dao_addr = *vector::borrow(dao_addresses, i);
            if (exists<DAOInfo>(dao_addr)) {
                let dao_info = borrow_global<DAOInfo>(dao_addr);
                let summary = DAOSummary {
                    address: dao_addr,
                    name: dao_info.name,
                    description: dao_info.description,
                    created_at: dao_info.created_at
                };
                vector::push_back(&mut result, summary);
            };
            i = i + 1;
        };
        
        result
    }

    // Check if a subname is available for use
    #[view]
    public fun is_subname_taken(subname: string::String): bool acquires SubnameRegistry {
        !is_subname_available(&subname)
    }

    // Get the DAO address that owns a specific subname
    #[view]
    public fun get_subname_owner(subname: string::String): address acquires SubnameRegistry {
        assert!(exists<SubnameRegistry>(@movedaoaddrx), errors::registry_not_initialized());
        let registry = borrow_global<SubnameRegistry>(@movedaoaddrx);
        assert!(simple_map::contains_key(&registry.used_subnames, &subname), errors::subname_not_found());
        *simple_map::borrow(&registry.used_subnames, &subname)
    }

    // Get total number of registered subnames
    #[view]
    public fun get_total_subnames(): u64 acquires SubnameRegistry {
        if (!exists<SubnameRegistry>(@movedaoaddrx)) return 0;
        let registry = borrow_global<SubnameRegistry>(@movedaoaddrx);
        registry.total_subnames
    }

    // Check if subname registry is initialized
    #[view]
    public fun is_subname_registry_initialized(): bool {
        exists<SubnameRegistry>(@movedaoaddrx)
    }

    // Get paginated DAOs (for better performance with large lists)
    #[view]
    public fun get_daos_paginated(offset: u64, limit: u64): vector<DAOSummary> acquires DAORegistry, DAOInfo {
        if (!exists<DAORegistry>(@movedaoaddrx)) {
            return vector::empty()
        };
        
        let registry = borrow_global<DAORegistry>(@movedaoaddrx);
        let dao_addresses = &registry.dao_addresses;
        let total_daos = vector::length(dao_addresses);
        let result = vector::empty<DAOSummary>();
        
        if (offset >= total_daos) {
            return result
        };
        
        let end = offset + limit;
        if (end > total_daos) {
            end = total_daos;
        };
        
        let i = offset;
        while (i < end) {
            let dao_addr = *vector::borrow(dao_addresses, i);
            if (exists<DAOInfo>(dao_addr)) {
                let dao_info = borrow_global<DAOInfo>(dao_addr);
                let summary = DAOSummary {
                    address: dao_addr,
                    name: dao_info.name,
                    description: dao_info.description,
                    created_at: dao_info.created_at
                };
                vector::push_back(&mut result, summary);
            };
            i = i + 1;
        };
        
        result
    }

    public entry fun claim_rewards(
        account: &signer,
        movedaoaddrx: address
    ) acquires DAOInfo {
        let user_addr = signer::address_of(account);
        
        // Enhanced access control checks
        // 1. Verify DAO exists
        assert!(exists<DAOInfo>(movedaoaddrx), errors::not_found());
        
        // 2. Verify user is a legitimate member/staker before checking rewards
        assert!(membership::is_member(movedaoaddrx, user_addr), errors::not_member());
        
        // 3. Additional validation: check if rewards system is enabled
        assert!(rewards::is_rewards_enabled(movedaoaddrx), errors::invalid_status());
        
        // 4. Get treasury object early for atomic operations
        let treasury_obj = get_treasury_object(movedaoaddrx);
        
        // 5. Atomic reward claiming with treasury validation
        // Check claimable amount and claim atomically to prevent race conditions
        let total_claimable = rewards::get_total_claimable(movedaoaddrx, user_addr);
        assert!(total_claimable > 0, errors::nothing_to_claim());
        
        // 6. Validate treasury has sufficient balance before claiming
        let treasury_balance = treasury::get_balance_from_object(treasury_obj);
        assert!(treasury_balance >= total_claimable, errors::insufficient_treasury());
        
        // 7. Process the claim and get the actual amount claimed (this should be atomic)
        let claimed_amount = rewards::claim_rewards_internal(movedaoaddrx, user_addr);
        
        // 8. Only proceed with treasury operations if there were actually rewards to claim
        if (claimed_amount > 0) {
            // 9. Final security checks with the actual claimed amount
            assert!(claimed_amount <= total_claimable, errors::invalid_amount()); // Prevent over-claiming
            assert!(membership::is_member(movedaoaddrx, user_addr), errors::not_member()); // Re-verify membership
            
            // 10. Transfer from treasury to user for rewards
            treasury::withdraw_rewards_from_object(user_addr, treasury_obj, claimed_amount);
        };
    }

    // Launchpad integration functions
    public entry fun create_dao_launchpad(
        admin: &signer,
        movedaoaddrx: address,
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
            movedaoaddrx,
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
            movedaoaddrxess: movedaoaddrx,
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
        movedaoaddrx: address,
        participants: vector<address>,
        tiers: vector<u8>,
        max_allocations: vector<u64>
    ) {
        launchpad::add_to_whitelist(admin, movedaoaddrx, participants, tiers, max_allocations);
    }
}