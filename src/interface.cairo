// src/interface.cairo
use starknet::ContractAddress;
use super::types::CharityRequest;

#[starknet::interface]
pub trait IChainHope<TContractState> {
    // ---- RECIPIENT ACTIONS ----
    fn submit_request(
        ref self: TContractState,
        ipfs_hash: felt252,
        title: felt252,
        amount_needed: u256,
    ) -> u64;

    // ---- COMMUNITY ACTIONS ----
    fn vote_approve(ref self: TContractState, request_id: u64);
    fn vote_reject(ref self: TContractState, request_id: u64);

    // ---- DONOR ACTIONS ----
    fn donate(ref self: TContractState, request_id: u64, amount: u256);

    // ---- ADMIN ACTIONS ----
    fn close_request(ref self: TContractState, request_id: u64);
    fn set_vote_threshold(ref self: TContractState, threshold: u64);
    fn set_accepted_token(ref self: TContractState, token: ContractAddress);
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
    fn accept_ownership(ref self: TContractState);
    fn propose_vote_threshold(ref self: TContractState, threshold: u64);
    fn execute_vote_threshold(ref self: TContractState);

    // ✅ ADDED — were in contract but missing from interface
    fn whitelist_token(ref self: TContractState, token: ContractAddress);
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);

    // ---- VIEW FUNCTIONS ----
    fn get_request(self: @TContractState, request_id: u64) -> CharityRequest;
    fn get_request_count(self: @TContractState) -> u64;
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn get_vote_threshold(self: @TContractState) -> u64;
    fn has_voted(
        self: @TContractState,
        request_id: u64,
        voter: ContractAddress
    ) -> bool;
    fn get_total_donated(self: @TContractState, request_id: u64) -> u256;
    fn get_accepted_token(self: @TContractState) -> ContractAddress;
    fn get_pending_owner(self: @TContractState) -> ContractAddress;

    // ✅ ADDED — were in contract but missing from interface
    fn is_paused(self: @TContractState) -> bool;
    fn is_token_whitelisted(
        self: @TContractState,
        token: ContractAddress
    ) -> bool;
}