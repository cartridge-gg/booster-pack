pub mod constants {
    pub mod identifier;
    pub mod interface;
    pub mod units;
}

pub mod main;
pub mod mocks {
    pub mod erc20_mock;
}

pub mod tests {
    pub mod test_integration;
}

// Re-export for tests
pub use main::{IClaim, IClaimDispatcher, IClaimDispatcherTrait, LeafDataWithExtraData, MysteryTokenConfig};
