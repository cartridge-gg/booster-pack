use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC20Token<T> {
    fn transfer(ref self: T, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: T, sender: ContractAddress, recipient: ContractAddress, amount: u256,
    ) -> bool;
}

#[starknet::interface]
pub trait IERC721Token<T> {
    fn transfer_from(ref self: T, from: ContractAddress, to: ContractAddress, token_id: u256);
    fn safe_transfer_from(ref self: T, from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>);
}
