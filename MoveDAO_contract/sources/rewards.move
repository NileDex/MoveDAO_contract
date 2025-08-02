module dao_addr::rewards {
    use std::signer;
    use std::vector;
    use std::simple_map::{Self, SimpleMap};
    use std::event;
    use aptos_framework::timestamp;
    use dao_addr::admin;

    const ENOT_ADMIN: u64 = 1;
    const EINVALID_REWARD_TYPE: u64 = 2;
    const EINSUFFICIENT_TREASURY: u64 = 3;
    const EREWARD_ALREADY_CLAIMED: u64 = 4;
    const EREWARD_NOT_FOUND: u64 = 5;
    const EINVALID_AMOUNT: u64 = 6;

    // Reward types
    const REWARD_VOTING: u8 = 1;
    const REWARD_PROPOSAL_CREATION: u8 = 2;
    const REWARD_STAKING: u8 = 3;
    const REWARD_PROPOSAL_SUCCESS: u8 = 4;

    struct RewardConfig has key {
        voting_reward_per_vote: u64,
        proposal_creation_reward: u64,
        successful_proposal_reward: u64,
        staking_yield_rate: u64, // Annual percentage (e.g., 500 = 5%)
        last_staking_distribution: u64,
        staking_distribution_interval: u64, // Seconds between distributions
        total_rewards_distributed: u64,
        enabled: bool
    }

    struct PendingReward has store, copy, drop {
        recipient: address,
        amount: u64,
        reward_type: u8,
        created_at: u64,
        claimed: bool,
        proposal_id: u64 // For proposal-related rewards
    }

    struct RewardTracker has key {
        pending_rewards: vector<PendingReward>,
        claimed_rewards: SimpleMap<address, u64>, // Total claimed by user
        next_reward_id: u64
    }

    #[event]
    struct RewardDistributed has drop, store {
        recipient: address,
        amount: u64,
        reward_type: u8,
        proposal_id: u64,
        distributed_at: u64
    }

    #[event]
    struct RewardClaimed has drop, store {
        recipient: address,
        amount: u64,
        reward_type: u8,
        claimed_at: u64
    }

    #[event]
    struct StakingRewardsDistributed has drop, store {
        total_amount: u64,
        total_recipients: u64,
        distributed_at: u64
    }

    public fun initialize_rewards(
        account: &signer,
        voting_reward_per_vote: u64,
        proposal_creation_reward: u64,
        successful_proposal_reward: u64,
        staking_yield_rate: u64,
        staking_distribution_interval: u64
    ) {
        let addr = signer::address_of(account);
        assert!(!exists<RewardConfig>(addr), 1);
        assert!(!exists<RewardTracker>(addr), 1);

        let config = RewardConfig {
            voting_reward_per_vote,
            proposal_creation_reward,
            successful_proposal_reward,
            staking_yield_rate,
            last_staking_distribution: timestamp::now_seconds(),
            staking_distribution_interval,
            total_rewards_distributed: 0,
            enabled: true
        };

        let tracker = RewardTracker {
            pending_rewards: vector::empty(),
            claimed_rewards: simple_map::new(),
            next_reward_id: 0
        };

        move_to(account, config);
        move_to(account, tracker);
    }

    public fun distribute_voting_reward(
        dao_addr: address,
        voter: address,
        proposal_id: u64
    ) acquires RewardConfig, RewardTracker {

        let config = borrow_global<RewardConfig>(dao_addr);
        if (!config.enabled) return;

        let amount = config.voting_reward_per_vote;
        if (amount == 0) return;

        create_pending_reward(dao_addr, voter, amount, REWARD_VOTING, proposal_id);
    }

    public fun distribute_proposal_creation_reward(
        dao_addr: address,
        proposer: address,
        proposal_id: u64
    ) acquires RewardConfig, RewardTracker {

        let config = borrow_global<RewardConfig>(dao_addr);
        if (!config.enabled) return;

        let amount = config.proposal_creation_reward;
        if (amount == 0) return;

        create_pending_reward(dao_addr, proposer, amount, REWARD_PROPOSAL_CREATION, proposal_id);
    }

    public fun distribute_successful_proposal_reward(
        dao_addr: address,
        proposer: address,
        proposal_id: u64
    ) acquires RewardConfig, RewardTracker {

        let config = borrow_global<RewardConfig>(dao_addr);
        if (!config.enabled) return;

        let amount = config.successful_proposal_reward;
        if (amount == 0) return;

        create_pending_reward(dao_addr, proposer, amount, REWARD_PROPOSAL_SUCCESS, proposal_id);
    }

    public entry fun distribute_staking_rewards(
        admin: &signer,
        dao_addr: address,
        stakers: vector<address>,
        staked_amounts: vector<u64>
    ) acquires RewardConfig, RewardTracker {
        assert!(admin::is_admin(dao_addr, signer::address_of(admin)), ENOT_ADMIN);
        assert!(vector::length(&stakers) == vector::length(&staked_amounts), EINVALID_AMOUNT);

        let config = borrow_global_mut<RewardConfig>(dao_addr);
        if (!config.enabled) return;

        let now = timestamp::now_seconds();
        let time_elapsed = now - config.last_staking_distribution;
        
        if (time_elapsed < config.staking_distribution_interval) return;

        let total_distributed = 0;
        let recipient_count = vector::length(&stakers);
        let i = 0;

        while (i < recipient_count) {
            let staker = *vector::borrow(&stakers, i);
            let staked_amount = *vector::borrow(&staked_amounts, i);
            
            if (staked_amount > 0) {
                // Calculate annual yield: (staked_amount * yield_rate * time_elapsed) / (365 * 24 * 3600 * 10000)
                let annual_seconds = 365 * 24 * 3600;
                let reward_amount = (staked_amount * config.staking_yield_rate * time_elapsed) / (annual_seconds * 10000);
                
                if (reward_amount > 0) {
                    create_pending_reward(dao_addr, staker, reward_amount, REWARD_STAKING, 0);
                    total_distributed = total_distributed + reward_amount;
                };
            };
            i = i + 1;
        };

        config.last_staking_distribution = now;
        
        event::emit(StakingRewardsDistributed {
            total_amount: total_distributed,
            total_recipients: recipient_count,
            distributed_at: now
        });
    }

    public fun claim_rewards_internal(
        dao_addr: address,
        user_addr: address
    ): u64 acquires RewardTracker, RewardConfig {
        let tracker = borrow_global_mut<RewardTracker>(dao_addr);
        let config = borrow_global_mut<RewardConfig>(dao_addr);
        
        let total_claimable = 0;
        let rewards_len = vector::length(&tracker.pending_rewards);
        let i = 0;

        // Calculate total claimable amount
        while (i < rewards_len) {
            let reward = vector::borrow(&tracker.pending_rewards, i);
            if (reward.recipient == user_addr && !reward.claimed) {
                total_claimable = total_claimable + reward.amount;
            };
            i = i + 1;
        };

        if (total_claimable == 0) return 0;

        // Mark rewards as claimed
        i = 0;
        while (i < rewards_len) {
            let reward = vector::borrow_mut(&mut tracker.pending_rewards, i);
            if (reward.recipient == user_addr && !reward.claimed) {
                reward.claimed = true;
                
                event::emit(RewardClaimed {
                    recipient: user_addr,
                    amount: reward.amount,
                    reward_type: reward.reward_type,
                    claimed_at: timestamp::now_seconds()
                });
            };
            i = i + 1;
        };

        // Update claimed totals
        if (simple_map::contains_key(&tracker.claimed_rewards, &user_addr)) {
            let current_total = simple_map::borrow_mut(&mut tracker.claimed_rewards, &user_addr);
            *current_total = *current_total + total_claimable;
        } else {
            simple_map::add(&mut tracker.claimed_rewards, user_addr, total_claimable);
        };

        config.total_rewards_distributed = config.total_rewards_distributed + total_claimable;
        total_claimable
    }

    public entry fun update_reward_config(
        admin: &signer,
        dao_addr: address,
        voting_reward_per_vote: u64,
        proposal_creation_reward: u64,
        successful_proposal_reward: u64,
        staking_yield_rate: u64
    ) acquires RewardConfig {
        assert!(admin::is_admin(dao_addr, signer::address_of(admin)), ENOT_ADMIN);
        
        let config = borrow_global_mut<RewardConfig>(dao_addr);
        config.voting_reward_per_vote = voting_reward_per_vote;
        config.proposal_creation_reward = proposal_creation_reward;
        config.successful_proposal_reward = successful_proposal_reward;
        config.staking_yield_rate = staking_yield_rate;
    }

    public entry fun toggle_rewards(
        admin: &signer,
        dao_addr: address,
        enabled: bool
    ) acquires RewardConfig {
        assert!(admin::is_admin(dao_addr, signer::address_of(admin)), ENOT_ADMIN);
        
        let config = borrow_global_mut<RewardConfig>(dao_addr);
        config.enabled = enabled;
    }

    #[view]
    public fun get_pending_rewards(dao_addr: address, user: address): vector<PendingReward> acquires RewardTracker {
        let tracker = borrow_global<RewardTracker>(dao_addr);
        let user_rewards = vector::empty();
        let len = vector::length(&tracker.pending_rewards);
        let i = 0;

        while (i < len) {
            let reward = vector::borrow(&tracker.pending_rewards, i);
            if (reward.recipient == user && !reward.claimed) {
                vector::push_back(&mut user_rewards, *reward);
            };
            i = i + 1;
        };

        user_rewards
    }

    #[view]
    public fun get_total_claimable(dao_addr: address, user: address): u64 acquires RewardTracker {
        let tracker = borrow_global<RewardTracker>(dao_addr);
        let total = 0;
        let len = vector::length(&tracker.pending_rewards);
        let i = 0;

        while (i < len) {
            let reward = vector::borrow(&tracker.pending_rewards, i);
            if (reward.recipient == user && !reward.claimed) {
                total = total + reward.amount;
            };
            i = i + 1;
        };

        total
    }

    #[view]
    public fun get_total_claimed(dao_addr: address, user: address): u64 acquires RewardTracker {
        let tracker = borrow_global<RewardTracker>(dao_addr);
        if (simple_map::contains_key(&tracker.claimed_rewards, &user)) {
            *simple_map::borrow(&tracker.claimed_rewards, &user)
        } else {
            0
        }
    }

    #[view]
    public fun get_reward_config(dao_addr: address): (u64, u64, u64, u64, u64, bool) acquires RewardConfig {
        let config = borrow_global<RewardConfig>(dao_addr);
        (
            config.voting_reward_per_vote,
            config.proposal_creation_reward,
            config.successful_proposal_reward,
            config.staking_yield_rate,
            config.total_rewards_distributed,
            config.enabled
        )
    }

    // Helper functions
    fun create_pending_reward(
        dao_addr: address,
        recipient: address,
        amount: u64,
        reward_type: u8,
        proposal_id: u64
    ) acquires RewardTracker {
        let tracker = borrow_global_mut<RewardTracker>(dao_addr);
        let now = timestamp::now_seconds();

        let reward = PendingReward {
            recipient,
            amount,
            reward_type,
            created_at: now,
            claimed: false,
            proposal_id
        };

        vector::push_back(&mut tracker.pending_rewards, reward);
        tracker.next_reward_id = tracker.next_reward_id + 1;

        event::emit(RewardDistributed {
            recipient,
            amount,
            reward_type,
            proposal_id,
            distributed_at: now
        });
    }

    // Public constants for reward types
    public fun reward_voting(): u8 { REWARD_VOTING }
    public fun reward_proposal_creation(): u8 { REWARD_PROPOSAL_CREATION }
    public fun reward_staking(): u8 { REWARD_STAKING }
    public fun reward_proposal_success(): u8 { REWARD_PROPOSAL_SUCCESS }
}