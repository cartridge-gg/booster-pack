pub const ERC_20: felt252 = 'ERC_20';
pub const ERC_721: felt252 = 'ERC_721';
pub const MYSTERY_ASSET: felt252 = 'MYSTERY_ASSET';

// Token Type Enum
#[derive(Drop, Copy, PartialEq)]
pub enum TokenType {
    ERC_20,
    ERC_721,
    MYSTERY_ASSET,
}

// Manual Serde implementation for TokenType
impl TokenTypeSerde of core::serde::Serde<TokenType> {
    fn serialize(self: @TokenType, ref output: Array<felt252>) {
        match self {
            TokenType::ERC_20 => ERC_20.serialize(ref output),
            TokenType::ERC_721 => ERC_721.serialize(ref output),
            TokenType::MYSTERY_ASSET => MYSTERY_ASSET.serialize(ref output),
        }
    }

    fn deserialize(ref serialized: Span<felt252>) -> Option<TokenType> {
        let felt_val = core::serde::Serde::<felt252>::deserialize(ref serialized)?;

        if felt_val == ERC_20 {
            Option::Some(TokenType::ERC_20)
        } else if felt_val == ERC_721 {
            Option::Some(TokenType::ERC_721)
        } else if felt_val == MYSTERY_ASSET {
            Option::Some(TokenType::MYSTERY_ASSET)
        } else {
            Option::None
        }
    }
}
