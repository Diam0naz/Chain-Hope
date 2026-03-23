pub mod Errors {
    pub const NOT_OWNER: felt252 = 'Caller is not owner';
    pub const INVALID_REQUEST: felt252 = 'Request does not exist';
    pub const ALREADY_VOTED: felt252 = 'Already voted on request';
    pub const REQUEST_NOT_PENDING: felt252 = 'Request is not pending';
    pub const REQUEST_NOT_APPROVED: felt252 = 'Request not approved';
    pub const ZERO_ADDRESS: felt252 = 'Zero address not allowed';
    pub const ZERO_AMOUNT: felt252 = 'Amount must be greater than 0';
    pub const ZERO_IPFS_HASH: felt252 = 'IPFS hash cannot be empty';
    pub const RECIPIENT_CANNOT_VOTE: felt252 = 'Recipient cannot vote';
    pub const RECIPIENT_CANNOT_DONATE: felt252 = 'Recipient cannot self donate';
    pub const REQUEST_NOT_ACTIVE: felt252 = 'Request is not active';
    pub const ALREADY_CLOSED: felt252 = 'Request already closed';
    pub const INSUFFICIENT_ALLOWANCE: felt252 = 'Insufficient token allowance';
    pub const TRANSFER_FAILED: felt252 = 'Token transfer failed';
    pub const INVALID_TOKEN: felt252 = 'Invalid token address';
    pub const OVERFLOW: felt252 = 'Arithmetic overflow';
    pub const TIMELOCK_NOT_EXPIRED: felt252 = 'Timelock has not expired';
    pub const TOKEN_NOT_WHITELISTED: felt252 = 'Token not whitelisted';
    pub const VOTE_WEIGHT_TOO_LOW: felt252 = 'Insufficient vote weight';
    pub const CONTRACT_PAUSED: felt252 = 'Contract is paused';
    pub const VOTING_CLOSED: felt252 = 'Voting period has closed';
}
