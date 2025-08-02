module dao_addr::dao_core {
    use std::signer;
    use std::string;
    use std::error;
    use aptos_framework::timestamp;
    use dao_addr::admin;
    use dao_addr::council;
    use dao_addr::membership;
    use dao_addr::proposal;
    use dao_addr::staking;
    use dao_addr::treasury;
    use dao_addr::rewards;
    use dao_addr::launchpad;
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

    public entry fun create_dao(
        account: &signer,
        name: string::String,
        description: string::String,
        logo: vector<u8>,
        background: vector<u8>,
        initial_council: vector<address>,
        _min_quorum_percent: u64, // Marked as unused with underscore
        min_voting_period: u64,
        max_voting_period: u64
    ) {
        let addr = signer::address_of(account);
        assert!(!exists<DAOInfo>(addr), error::already_exists(0));

        let council = council::init_council(account, initial_council, 1, 10);
        let treasury = treasury::init_treasury(account);

        move_to(account, DAOInfo {
            name,
            description,
            logo,
            background,
            created_at: timestamp::now_seconds(),
            council,
            treasury
        });

        // Initialize all required modules
        admin::init_admin(account, 1);
        membership::initialize(account);
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
        let total_claimable = rewards::claim_rewards_internal(dao_addr, user_addr);
        
        if (total_claimable > 0) {
            // Check treasury has sufficient funds and withdraw
            let treasury_obj = get_treasury_object(dao_addr);
            let treasury_balance = treasury::get_balance_from_object(treasury_obj);
            assert!(treasury_balance >= total_claimable, 3); // EINSUFFICIENT_TREASURY
            
            // Transfer from treasury to user for rewards (bypasses admin check)
            treasury::withdraw_rewards_from_object(user_addr, treasury_obj, total_claimable);
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