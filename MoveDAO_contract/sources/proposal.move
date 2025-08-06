// Proposal system - handles creating, voting on, and executing community governance proposals
module dao_addr::proposal {
    use std::signer;
    use std::vector;
    use std::string;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use dao_addr::admin;
    use dao_addr::membership;
    use dao_addr::staking;
    use dao_addr::rewards;
    use dao_addr::errors;

    // Proposal Status Enum
    struct ProposalStatus has copy, drop, store {
        value: u8
    }

    // Status constructors
    public fun status_draft(): ProposalStatus { ProposalStatus { value: 0 } }
    public fun status_active(): ProposalStatus { ProposalStatus { value: 1 } }
    public fun status_passed(): ProposalStatus { ProposalStatus { value: 2 } }
    public fun status_rejected(): ProposalStatus { ProposalStatus { value: 3 } }
    public fun status_executed(): ProposalStatus { ProposalStatus { value: 4 } }
    public fun status_cancelled(): ProposalStatus { ProposalStatus { value: 5 } }

    // Status checkers
    public fun is_draft(status: &ProposalStatus): bool { status.value == 0 }
    public fun is_active(status: &ProposalStatus): bool { status.value == 1 }
    public fun is_passed(status: &ProposalStatus): bool { status.value == 2 }
    public fun is_rejected(status: &ProposalStatus): bool { status.value == 3 }
    public fun is_executed(status: &ProposalStatus): bool { status.value == 4 }
    public fun is_cancelled(status: &ProposalStatus): bool { status.value == 5 }

    // Get status value for events and external use
    public fun get_status_value(status: &ProposalStatus): u8 { status.value }

    // Vote Type Enum
    struct VoteType has copy, drop, store {
        value: u8
    }

    // Vote type constructors
    public fun vote_yes(): VoteType { VoteType { value: 1 } }
    public fun vote_no(): VoteType { VoteType { value: 2 } }
    public fun vote_abstain(): VoteType { VoteType { value: 3 } }

    // Vote type checkers
    public fun is_yes_vote(vote_type: &VoteType): bool { vote_type.value == 1 }
    public fun is_no_vote(vote_type: &VoteType): bool { vote_type.value == 2 }
    public fun is_abstain_vote(vote_type: &VoteType): bool { vote_type.value == 3 }

    // Get vote type value
    public fun get_vote_type_value(vote_type: &VoteType): u8 { vote_type.value }


    struct Proposal has store, copy, drop {
        id: u64,
        title: string::String,
        description: string::String,
        proposer: address,
        status: ProposalStatus,
        votes: vector<Vote>,
        yes_votes: u64,
        no_votes: u64,
        abstain_votes: u64,
        created_at: u64,
        voting_start: u64,
        voting_end: u64,
        execution_window: u64,
        min_quorum_percent: u64
    }

    struct Vote has store, copy, drop {
        voter: address,
        vote_type: VoteType,
        weight: u64,
        voted_at: u64
    }

    struct DaoProposals has key {
        proposals: vector<Proposal>,
        next_id: u64,
        min_voting_period: u64,
        max_voting_period: u64,
    }

    #[event]
    struct ProposalCreatedEvent has drop, store {
        proposal_id: u64,
        proposer: address,
        title: string::String,
    }

    #[event]
    struct ProposalStatusChangedEvent has drop, store {
        proposal_id: u64,
        old_status: u8,
        new_status: u8,
        reason: string::String,
    }

    #[event]
    struct VoteCastEvent has drop, store {
        proposal_id: u64,
        voter: address,
        vote_type: u8,
        weight: u64,
    }

    public fun initialize_proposals(
        account: &signer,
        min_voting_period: u64,
        max_voting_period: u64
    ) {
        let addr = signer::address_of(account);
        if (!exists<DaoProposals>(addr)) {
            let dao_proposals = DaoProposals {
                proposals: vector::empty(),
                next_id: 0,
                min_voting_period,
                max_voting_period,
            };

            move_to(account, dao_proposals);
        } else {
            // If already exists, abort
            abort errors::not_authorized()
        }
    }

    public entry fun create_proposal(
        account: &signer,
        dao_addr: address,
        title: string::String,
        description: string::String,
        voting_duration_secs: u64,
        execution_window_secs: u64,
        min_quorum_percent: u64
    ) acquires DaoProposals {
        let sender = signer::address_of(account);
        assert!(admin::is_admin(dao_addr, sender) || membership::is_member(dao_addr, sender), errors::not_authorized());

        let proposals = borrow_global_mut<DaoProposals>(dao_addr);
        assert!(voting_duration_secs >= proposals.min_voting_period, errors::invalid_status());
        assert!(voting_duration_secs <= proposals.max_voting_period, errors::invalid_status());

        let now = timestamp::now_seconds();
        let proposal_id = proposals.next_id;

        let proposal = Proposal {
            id: proposal_id,
            title,
            description,
            proposer: sender,
            status: status_draft(),
            votes: vector::empty(),
            yes_votes: 0,
            no_votes: 0,
            abstain_votes: 0,
            created_at: now,
            voting_start: now,
            voting_end: now + voting_duration_secs,
            execution_window: execution_window_secs,
            min_quorum_percent
        };

        vector::push_back(&mut proposals.proposals, proposal);
        proposals.next_id = proposal_id + 1;
        
        event::emit(ProposalCreatedEvent {
            proposal_id,
            proposer: sender,
            title: copy title,
        });

        // Distribute proposal creation reward
        rewards::distribute_proposal_creation_reward(dao_addr, sender, proposal_id);
    }

    public entry fun start_voting(
        account: &signer,
        dao_addr: address,
        proposal_id: u64
    ) acquires DaoProposals {
        let sender = signer::address_of(account);
        let proposals = borrow_global_mut<DaoProposals>(dao_addr);
        let proposal = find_proposal_mut(&mut proposals.proposals, proposal_id);

        assert!(is_draft(&proposal.status), errors::invalid_status());
        assert!(
            proposal.proposer == sender || admin::is_admin(dao_addr, sender), 
            errors::not_admin_or_proposer()
        );

        proposal.status = status_active();
        event::emit(ProposalStatusChangedEvent {
            proposal_id,
            old_status: get_status_value(&status_draft()),
            new_status: get_status_value(&status_active()),
            reason: string::utf8(b"voting_started")
        });
    }

    public entry fun cast_vote(
        account: &signer,
        dao_addr: address,
        proposal_id: u64,
        vote_type: u8
    ) acquires DaoProposals {
        assert!(vote_type == 1 || vote_type == 2 || vote_type == 3, errors::invalid_vote_type());
        
        let sender = signer::address_of(account);
        assert!(membership::is_member(dao_addr, sender), errors::not_member());
        
        let proposals = borrow_global_mut<DaoProposals>(dao_addr);
        let proposal = find_proposal_mut(&mut proposals.proposals, proposal_id);

        assert!(is_active(&proposal.status), errors::invalid_status());
        let now = timestamp::now_seconds();
        assert!(now >= proposal.voting_start, errors::voting_not_started());
        assert!(now <= proposal.voting_end, errors::voting_ended());

        let i = 0;
        let len = vector::length(&proposal.votes);
        while (i < len) {
            let vote = vector::borrow(&proposal.votes, i);
            if (vote.voter == sender) abort errors::already_voted();
            i = i + 1;
        };

        // Get voting power directly from staking balance to prevent race conditions
        let weight = staking::get_staked_balance(sender);
        assert!(weight > 0, errors::not_member());
        
        // Double-check via membership module for consistency
        let membership_power = membership::get_voting_power(dao_addr, sender);
        assert!(weight == membership_power, errors::invalid_amount());
        
        let vote_enum = if (vote_type == 1) {
            vote_yes()
        } else if (vote_type == 2) {
            vote_no()
        } else {
            vote_abstain()
        };
        
        vector::push_back(&mut proposal.votes, Vote { 
            voter: sender, 
            vote_type: vote_enum, 
            weight,
            voted_at: now
        });

        // Add overflow protection for vote counting
        if (vote_type == 1) {
            assert!(proposal.yes_votes <= (18446744073709551615u64 - weight), errors::invalid_amount());
            proposal.yes_votes = proposal.yes_votes + weight;
        } else if (vote_type == 2) {
            assert!(proposal.no_votes <= (18446744073709551615u64 - weight), errors::invalid_amount());
            proposal.no_votes = proposal.no_votes + weight;
        } else {
            assert!(proposal.abstain_votes <= (18446744073709551615u64 - weight), errors::invalid_amount());
            proposal.abstain_votes = proposal.abstain_votes + weight;
        };

        event::emit(VoteCastEvent {
            proposal_id,
            voter: sender,
            vote_type,
            weight,
        });

        // Distribute voting reward
        rewards::distribute_voting_reward(dao_addr, sender, proposal_id);
    }

    public entry fun finalize_proposal(
        account: &signer,
        dao_addr: address,
        proposal_id: u64
    ) acquires DaoProposals {
        let _sender = signer::address_of(account);
        let proposals = borrow_global_mut<DaoProposals>(dao_addr);
        let proposal = find_proposal_mut(&mut proposals.proposals, proposal_id);

        assert!(is_active(&proposal.status), errors::invalid_status());
        let now = timestamp::now_seconds();
        assert!(now >= proposal.voting_end, errors::voting_ended());

        let total_staked = staking::get_total_staked(dao_addr);
        let total_votes = proposal.yes_votes + proposal.no_votes + proposal.abstain_votes;
        
        // Ensure votes cannot exceed total staked amount (critical security check)
        assert!(total_votes <= total_staked, errors::invalid_amount());
        
        let quorum = if (total_staked > 0) {
            (total_votes * 100) / total_staked
        } else {
            0
        };
        
        if (quorum < proposal.min_quorum_percent) {
            let old_status = get_status_value(&proposal.status);
            proposal.status = status_rejected();
            event::emit(ProposalStatusChangedEvent {
                proposal_id,
                old_status,
                new_status: get_status_value(&status_rejected()),
                reason: string::utf8(b"quorum_not_met")
            });
            return
        };

        let new_status_enum = if (proposal.yes_votes > proposal.no_votes) status_passed() else status_rejected();
        let old_status = get_status_value(&proposal.status);
        let new_status = get_status_value(&new_status_enum);
        proposal.status = new_status_enum;
        
        event::emit(ProposalStatusChangedEvent {
            proposal_id,
            old_status,
            new_status,
            reason: string::utf8(b"vote_majority")
        });

        // Distribute successful proposal reward if it passed
        if (is_passed(&proposal.status)) {
            rewards::distribute_successful_proposal_reward(dao_addr, proposal.proposer, proposal_id);
        };
    }

    public entry fun execute_proposal(
        account: &signer,
        dao_addr: address,
        proposal_id: u64
    ) acquires DaoProposals {
        let sender = signer::address_of(account);
        let proposals = borrow_global_mut<DaoProposals>(dao_addr);
        let proposal = find_proposal_mut(&mut proposals.proposals, proposal_id);

        assert!(is_passed(&proposal.status), errors::invalid_status());
        assert!(
            admin::is_admin(dao_addr, sender) || proposal.proposer == sender, 
            errors::not_admin_or_proposer()
        );
        
        let now = timestamp::now_seconds();
        assert!(now <= proposal.voting_end + proposal.execution_window, errors::execution_window_expired());

        let old_status = get_status_value(&proposal.status);
        proposal.status = status_executed();
        
        event::emit(ProposalStatusChangedEvent {
            proposal_id,
            old_status,
            new_status: get_status_value(&status_executed()),
            reason: string::utf8(b"executed")
        });
    }

    public entry fun cancel_proposal(
        account: &signer,
        dao_addr: address,
        proposal_id: u64
    ) acquires DaoProposals {
        let sender = signer::address_of(account);
        let proposals = borrow_global_mut<DaoProposals>(dao_addr);
        let proposal = find_proposal_mut(&mut proposals.proposals, proposal_id);

        assert!(
            is_draft(&proposal.status) || is_active(&proposal.status),
            errors::cannot_cancel()
        );
        assert!(
            admin::is_admin(dao_addr, sender) || proposal.proposer == sender,
            errors::not_admin_or_proposer()
        );

        let old_status = get_status_value(&proposal.status);
        proposal.status = status_cancelled();
        
        event::emit(ProposalStatusChangedEvent {
            proposal_id,
            old_status,
            new_status: get_status_value(&status_cancelled()),
            reason: string::utf8(b"cancelled")
        });
    }

    #[view]
    public fun get_proposal_status(dao_addr: address, proposal_id: u64): u8 acquires DaoProposals {
        let proposals = &borrow_global<DaoProposals>(dao_addr).proposals;
        let proposal = find_proposal(proposals, proposal_id);
        get_status_value(&proposal.status)
    }

    #[view]
    public fun get_proposal(dao_addr: address, proposal_id: u64): Proposal acquires DaoProposals {
        let proposals = &borrow_global<DaoProposals>(dao_addr).proposals;
        let proposal = find_proposal(proposals, proposal_id);
        *proposal
    }

    #[view]
    public fun get_proposals_count(dao_addr: address): u64 acquires DaoProposals {
        vector::length(&borrow_global<DaoProposals>(dao_addr).proposals)
    }

    fun find_proposal(proposals: &vector<Proposal>, proposal_id: u64): &Proposal {
        let i = 0;
        while (i < vector::length(proposals)) {
            let proposal = vector::borrow(proposals, i);
            if (proposal.id == proposal_id) return proposal;
            i = i + 1;
        };
        abort errors::no_such_proposal()
    }

    fun find_proposal_mut(proposals: &mut vector<Proposal>, proposal_id: u64): &mut Proposal {
        let i = 0;
        while (i < vector::length(proposals)) {
            let proposal = vector::borrow_mut(proposals, i);
            if (proposal.id == proposal_id) return proposal;
            i = i + 1;
        };
        abort errors::no_such_proposal()
    }

    #[view] public fun get_status_draft(): u8 { get_status_value(&status_draft()) }
    #[view] public fun get_status_active(): u8 { get_status_value(&status_active()) }
    #[view] public fun get_status_passed(): u8 { get_status_value(&status_passed()) }
    #[view] public fun get_status_rejected(): u8 { get_status_value(&status_rejected()) }
    #[view] public fun get_status_executed(): u8 { get_status_value(&status_executed()) }
    #[view] public fun get_status_cancelled(): u8 { get_status_value(&status_cancelled()) }
    
    #[view] public fun get_vote_yes(): u8 { get_vote_type_value(&vote_yes()) }
    #[view] public fun get_vote_no(): u8 { get_vote_type_value(&vote_no()) }
    #[view] public fun get_vote_abstain(): u8 { get_vote_type_value(&vote_abstain()) }
}