use starknet::ContractAddress;

#[derive(Drop, starknet::Event)]
pub struct RequestSubmitted {
    #[key]
    pub request_id: u64,
    #[key]
    pub recipient: ContractAddress,
    pub ipfs_hash: felt252,
    pub amount_needed: u256,
}

#[derive(Drop, starknet::Event)]
pub struct VoteCast {
    #[key]
    pub request_id: u64,
    #[key]
    pub voter: ContractAddress,
    pub approved: bool,
}

#[derive(Drop, starknet::Event)]
pub struct RequestApproved {
    #[key]
    pub request_id: u64,
    pub votes_for: u64,
}

#[derive(Drop, starknet::Event)]
pub struct RequestRejected {
    #[key]
    pub request_id: u64,
    pub votes_against: u64,
}

#[derive(Drop, starknet::Event)]
pub struct DonationReceived {
    #[key]
    pub request_id: u64,
    #[key]
    pub donor: ContractAddress,
    pub amount: u256,
    pub total_raised: u256,
}

#[derive(Drop, starknet::Event)]
pub struct RequestFunded {
    #[key]
    pub request_id: u64,
    pub recipient: ContractAddress,
    pub total_amount: u256,
}

#[derive(Drop, starknet::Event)]
pub struct RequestClosed {
    #[key]
    pub request_id: u64,
}

#[derive(Drop, starknet::Event)]
pub struct OwnershipTransferStarted {
    #[key]
    pub previous_owner: ContractAddress,
    #[key]
    pub new_owner: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct OwnershipTransferred {
    #[key]
    pub previous_owner: ContractAddress,
    #[key]
    pub new_owner: ContractAddress,
}
