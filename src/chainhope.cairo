#[starknet::contract]
pub mod ChainHope {
    use openzeppelin::security::reentrancyguard::ReentrancyGuardComponent;
    use starknet::event::EventEmitter;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};
    use crate::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use crate::errors::Errors;
    use crate::events::{
        DonationReceived, OwnershipTransferStarted, OwnershipTransferred, RequestApproved,
        RequestClosed, RequestFunded, RequestRejected, RequestSubmitted, VoteCast,
    };
    use crate::interface::IChainHope;
    use crate::types::{CharityRequest, RequestStatus};

    component!(
        path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent,
    );

    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;
    const TIMELOCK_DELAY: u64 = 86400;

    // ---- STORAGE ----
    #[storage]
    struct Storage {
        // Contract admin
        owner: ContractAddress,
        // Vote threshold — how many votes needed to approve/reject
        vote_threshold: u64,
        // Total number of requests submitted
        request_count: u64,
        // request_id → CharityRequest
        requests: Map<u64, CharityRequest>,
        // (request_id, voter_address) → has_voted bool
        has_voted: Map<(u64, ContractAddress), bool>,
        // (request_id, voter_address) → voted_approve bool
        voted_approve: Map<(u64, ContractAddress), bool>,
        // request_id → total donated amount
        total_donated: Map<u64, u256>,
        // Token sent
        accepted_token: ContractAddress,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
        // Prevents cheap sybil attacks
        min_vote_stake: u256,
        // ✅ Pause mechanism — owner can pause in emergency
        is_paused: bool,
        // ✅ Track voter stakes
        voter_stakes: Map<ContractAddress, u256>,
        // ✅ Only whitelisted tokens accepted
        whitelisted_tokens: Map<ContractAddress, bool>,
        // ✅ Two step ownership transfer
        pending_owner: ContractAddress,
        // ✅ Pending threshold change with timelock
        pending_threshold: u64,
        threshold_change_time: u64,
    }

    // ---- EVENTS ----
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        RequestSubmitted: RequestSubmitted,
        VoteCast: VoteCast,
        RequestApproved: RequestApproved,
        RequestRejected: RequestRejected,
        DonationReceived: DonationReceived,
        RequestFunded: RequestFunded,
        RequestClosed: RequestClosed,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        OwnershipTransferStarted: OwnershipTransferStarted,
        OwnershipTransferred: OwnershipTransferred,
    }

    // ---- CONSTRUCTOR ----
    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        vote_threshold: u64,
        accepted_token: ContractAddress,
    ) {
        assert(owner != 0.try_into().unwrap(), Errors::ZERO_ADDRESS);
        assert(accepted_token != 0.try_into().unwrap(), Errors::ZERO_ADDRESS);
        assert(vote_threshold > 0, Errors::ZERO_AMOUNT);

        self.owner.write(owner);
        self.vote_threshold.write(vote_threshold);
        self.accepted_token.write(accepted_token);
        self.request_count.write(0);
    }

    // ---- INTERNAL HELPERS ----
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _only_owner(self: @ContractState) {
            assert(get_caller_address() == self.owner.read(), Errors::NOT_OWNER);
        }

        fn _request_exists(self: @ContractState, request_id: u64) {
            assert(request_id < self.request_count.read(), Errors::INVALID_REQUEST);
        }

        fn _not_paused(self: @ContractState) {
            assert(!self.is_paused.read(), Errors::CONTRACT_PAUSED);
        }

        fn _valid_token(self: @ContractState, token: ContractAddress) {
            assert(self.whitelisted_tokens.read(token), Errors::INVALID_TOKEN);
        }

        fn _check_and_update_status(ref self: ContractState, request_id: u64) {
            let mut request = self.requests.read(request_id);
            let threshold = self.vote_threshold.read();

            // Check if votes_for hit threshold → approve
            if request.votes_for >= threshold {
                request.status = RequestStatus::Approved;
                self.requests.write(request_id, request);
                self.emit(RequestApproved { request_id, votes_for: request.votes_for });
            }

            // Check if votes_against hit threshold → reject
            if request.votes_against >= threshold {
                request.status = RequestStatus::Rejected;
                self.requests.write(request_id, request);
                self.emit(RequestRejected { request_id, votes_against: request.votes_against });
            }
        }
    }

    // ---- EXTERNAL FUNCTIONS ----
    #[abi(embed_v0)]
    impl ChainHopeImpl of IChainHope<ContractState> {
        // SUBMIT REQUEST
        fn submit_request(
            ref self: ContractState, ipfs_hash: felt252, title: felt252, amount_needed: u256,
        ) -> u64 {
            let caller = get_caller_address();

            // Validations
            assert(caller != 0.try_into().unwrap(), Errors::ZERO_ADDRESS);
            assert(ipfs_hash != 0, Errors::ZERO_IPFS_HASH);
            assert(amount_needed > 0, Errors::ZERO_AMOUNT);

            // Get next ID
            let request_id = self.request_count.read();

            // Build request
            let request = CharityRequest {
                id: request_id,
                recipient: caller,
                ipfs_hash,
                title,
                amount_needed,
                amount_raised: 0,
                status: RequestStatus::Pending,
                votes_for: 0,
                votes_against: 0,
                created_at: get_block_timestamp(),
                donor_count: 0,
            };

            // Save to storage
            self.requests.write(request_id, request);
            self.request_count.write(request_id + 1);

            // Emit event
            self.emit(RequestSubmitted { request_id, recipient: caller, ipfs_hash, amount_needed });

            request_id
        }

        // VOTE APPROVE
        fn vote_approve(ref self: ContractState, request_id: u64) {
            self._not_paused();
            self.reentrancy_guard.start();

            let caller = get_caller_address();
            self._request_exists(request_id);

            let request = self.requests.read(request_id);

            // Validations
            assert(request.status == RequestStatus::Pending, Errors::REQUEST_NOT_PENDING);
            assert(!self.has_voted.read((request_id, caller)), Errors::ALREADY_VOTED);
            assert(request.recipient != caller, Errors::RECIPIENT_CANNOT_VOTE);

            // Record vote
            self.has_voted.write((request_id, caller), true);
            self.voted_approve.write((request_id, caller), true);

            // Update vote count
            let mut updated = self.requests.read(request_id);
            updated.votes_for += 1;
            self.requests.write(request_id, updated);

            // Emit event
            self.emit(VoteCast { request_id, voter: caller, approved: true });

            // Check if threshold reached
            self._check_and_update_status(request_id);

            self.reentrancy_guard.end();
        }

        // VOTE REJECT
        fn vote_reject(ref self: ContractState, request_id: u64) {
            self._not_paused();
            self.reentrancy_guard.start();

            let caller = get_caller_address();
            self._request_exists(request_id);

            let request = self.requests.read(request_id);

            // Validations
            assert(request.status == RequestStatus::Pending, Errors::REQUEST_NOT_PENDING);
            assert(!self.has_voted.read((request_id, caller)), Errors::ALREADY_VOTED);
            assert(request.recipient != caller, Errors::RECIPIENT_CANNOT_VOTE);

            // Record vote
            self.has_voted.write((request_id, caller), true);
            self.voted_approve.write((request_id, caller), false);

            // Update vote count
            let mut updated = self.requests.read(request_id);
            updated.votes_against += 1;
            self.requests.write(request_id, updated);

            // Emit event
            self.emit(VoteCast { request_id, voter: caller, approved: false });

            // Check if threshold reached
            self._check_and_update_status(request_id);

            self.reentrancy_guard.end();
        }

        // DONATE
        fn donate(ref self: ContractState, request_id: u64, amount: u256) {
            self._not_paused();
            self.reentrancy_guard.start();

            let caller = get_caller_address();
            self._request_exists(request_id);

            let mut request = self.requests.read(request_id);

            assert(
                request.status == RequestStatus::Approved
                    || request.status == RequestStatus::Funded,
                Errors::REQUEST_NOT_APPROVED,
            );
            assert(request.recipient != caller, Errors::RECIPIENT_CANNOT_DONATE);
            assert(amount > 0, Errors::ZERO_AMOUNT);

            let token_address = self.accepted_token.read();
            let contract_address = get_contract_address();
            let token = IERC20Dispatcher { contract_address: token_address };

            let allowance = token.allowance(caller, contract_address);
            assert(allowance >= amount, Errors::INSUFFICIENT_ALLOWANCE);

            // Overflow check
            let new_amount_raised = request.amount_raised + amount;
            assert(new_amount_raised >= request.amount_raised, Errors::OVERFLOW);

            request.amount_raised = new_amount_raised;
            request.donor_count += 1;
            self.requests.write(request_id, request);

            let current = self.total_donated.read(request_id);
            self.total_donated.write(request_id, current + amount);

            // External calls AFTER state updates
            let pull_success = token.transfer_from(caller, contract_address, amount);
            assert(pull_success, Errors::TRANSFER_FAILED);

            let push_success = token.transfer(request.recipient, amount);
            assert(push_success, Errors::TRANSFER_FAILED);

            self
                .emit(
                    DonationReceived {
                        request_id, donor: caller, amount, total_raised: request.amount_raised,
                    },
                );

            if request.amount_raised >= request.amount_needed {
                let mut funded = self.requests.read(request_id);
                funded.status = RequestStatus::Funded;
                self.requests.write(request_id, funded);
                self
                    .emit(
                        RequestFunded {
                            request_id,
                            recipient: request.recipient,
                            total_amount: request.amount_raised,
                        },
                    );
            }

            self.reentrancy_guard.end();
        }

        fn whitelist_token(ref self: ContractState, token: ContractAddress) {
            self._only_owner();
            assert(token != 0.try_into().unwrap(), Errors::ZERO_ADDRESS);
            self.whitelisted_tokens.write(token, true);
        }

        fn pause(ref self: ContractState) {
            self._only_owner();
            self.is_paused.write(true);
        }

        fn unpause(ref self: ContractState) {
            self._only_owner();
            self.is_paused.write(false);
        }


        fn is_paused(self: @ContractState) -> bool {
            self.is_paused.read()
        }

        fn is_token_whitelisted(self: @ContractState, token: ContractAddress) -> bool {
            self.whitelisted_tokens.read(token)
        }

        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            self._only_owner();
            assert(new_owner != 0.try_into().unwrap(), Errors::ZERO_ADDRESS);
            // ✅ Stage the transfer — doesn't take effect immediately
            self.pending_owner.write(new_owner);
            // self.emit(OwnershipTransferStarted { previous_owner: self.owner.read(), new_owner });
            self.emit(OwnershipTransferStarted { previous_owner: self.owner.read(), new_owner });
        }

        fn accept_ownership(ref self: ContractState) {
            let caller = get_caller_address();
            // ✅ Only pending owner can accept
            assert(caller == self.pending_owner.read(), Errors::NOT_OWNER);
            let old_owner = self.owner.read();
            self.owner.write(caller);
            self.pending_owner.write(0.try_into().unwrap());
            self.emit(OwnershipTransferred { previous_owner: old_owner, new_owner: caller });
        }

        fn propose_vote_threshold(ref self: ContractState, threshold: u64) {
            self._only_owner();
            assert(threshold > 0, Errors::ZERO_AMOUNT);
            self.pending_threshold.write(threshold);
            // ✅ Can only execute after 24 hours
            self.threshold_change_time.write(get_block_timestamp() + TIMELOCK_DELAY);
        }

        fn execute_vote_threshold(ref self: ContractState) {
            self._only_owner();
            assert(
                get_block_timestamp() >= self.threshold_change_time.read(),
                Errors::TIMELOCK_NOT_EXPIRED,
            );
            self.vote_threshold.write(self.pending_threshold.read());
        }


        fn set_accepted_token(ref self: ContractState, token: ContractAddress) {
            self._only_owner();
            assert(token != 0.try_into().unwrap(), Errors::INVALID_TOKEN);
            self.accepted_token.write(token);
        }


        // CLOSE REQUEST
        fn close_request(ref self: ContractState, request_id: u64) {
            self._not_paused();
            self.reentrancy_guard.start();
            self._only_owner();
            self._request_exists(request_id);

            let mut request = self.requests.read(request_id);
            assert(request.status != RequestStatus::Closed, Errors::ALREADY_CLOSED);

            request.status = RequestStatus::Closed;
            self.requests.write(request_id, request);

            self.emit(RequestClosed { request_id });
            self.reentrancy_guard.end();
        }

        // SET VOTE THRESHOLD
        fn set_vote_threshold(ref self: ContractState, threshold: u64) {
            self._only_owner();
            assert(threshold > 0, Errors::ZERO_AMOUNT);
            self.vote_threshold.write(threshold);
        }

        // ---- VIEW FUNCTIONS ----
        fn get_request(self: @ContractState, request_id: u64) -> CharityRequest {
            self._request_exists(request_id);
            self.requests.read(request_id)
        }

        fn get_request_count(self: @ContractState) -> u64 {
            self.request_count.read()
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn get_vote_threshold(self: @ContractState) -> u64 {
            self.vote_threshold.read()
        }

        fn has_voted(self: @ContractState, request_id: u64, voter: ContractAddress) -> bool {
            self.has_voted.read((request_id, voter))
        }

        fn get_total_donated(self: @ContractState, request_id: u64) -> u256 {
            self.total_donated.read(request_id)
        }

        fn get_accepted_token(self: @ContractState) -> ContractAddress {
            self.accepted_token.read()
        }

        fn get_pending_owner(self: @ContractState) -> ContractAddress {
            self.pending_owner.read()
        }
    }
}
 