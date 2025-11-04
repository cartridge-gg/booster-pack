use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC20Token<T> {
    fn transfer_from(
        ref self: T, sender: ContractAddress, recipient: ContractAddress, amount: u256,
    );
}

#[starknet::interface]
pub trait IERC721Token<T> {
    fn transfer_from(ref self: T, from: ContractAddress, to: ContractAddress, token_id: u256);
}
