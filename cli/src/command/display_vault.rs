use solana_sdk::pubkey::Pubkey;
use squads_multisig::pda::get_vault_pda;
use std::str::FromStr;

use clap::Args;

use crate::utils::resolve_program_id;

/// Derive and display the vault PDA address for a given multisig and vault index.
#[derive(Args)]
pub struct DisplayVault {
    /// Multisig Program ID
    #[arg(long)]
    program_id: Option<String>,

    /// Path to the Program Config Initializer Keypair
    #[arg(long)]
    multisig_address: String,

    // index to derive the vault, default 0
    #[arg(long)]
    vault_index: Option<u8>,
}

impl DisplayVault {
    pub async fn execute(self) -> eyre::Result<()> {
        let Self {
            program_id,
            multisig_address,
            vault_index,
        } = self;

        let program_id = resolve_program_id(program_id);

        let multisig_address =
            Pubkey::from_str(&multisig_address).expect("Invalid multisig address");

        let vault_index = vault_index.unwrap_or(0);

        let vault_address = get_vault_pda(&multisig_address, vault_index, Some(&program_id));

        println!("Vault: {:?}", vault_address);

        Ok(())
    }
}
