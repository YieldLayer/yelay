# Yelay: Governance Contracts

- Governance contracts for the Yelay protocol - token, staking (with staking power accumulation), and migration from SPOOL governance contracts.

# Goal

- Migrate existing SPOOl token ecosystem to the new one - Yelay.

# Contracts: Overview

Before - Now table 
- SpoolOwner => YelayOwner
- SPOOL => YLAY
- voSPOOL => sYLAY (inherits sYLAYBase which ultimately is voSPOOL with small changes in logic + changed YelayOwner and renaming)
- voSpoolRewards => sYLAYRewards (YelayOwner + renaming)
- SpoolStaking => YelayStaking (inherits YelayStakingBase which ultimately is SpoolStaking, changed YelayOwner + renaming)
- RewardsDistributor => YelayRewardsDistributor (YelayOwner + renaming)

YelayMigrator is a new contract which will be used solely for migration purposes. 
Once it is finished it will be no longer used.

All previous contracts for SPOOL ecosystem can be found in spool-staking-and-voting submodule.

### YLAY
Token for Yelay.  
- Upgradeable UUPS proxy with Pausable functionality.
- On deployment, it mints all supply to itself. From here, either the admin or the Migrator contract may call `claim` to transfer tokens to the necessary users as they are verified in the `YelayMigrator` contract. It is done this way (rather than direct `_mint` in `claim`) so that the total supply exists immediately when the contract is created.

---

### YelayMigrator
- Responsible for migration of SPOOL tokens/staked amounts to the new Yelay system.  

- Spool tokens are migrated at a rate of 1 SPOOL:7.1428 YELAY (140m (210m supply - 70m sent to 0xdead address) / 1B supply).

- `migrateBalance`: any user with SPOOL balance at the time of the SPOOL token pause may call this function to mint YELAY to their address in the ratio defined above. If they are in the blocklist, they may not call this function. The admin may call this function with a list of users to migrate. It is expected that users will call this function themselves, should they have balance.

- `migrateStake`: The admin may call this function with a list of users to migrate. It is expected that the admin will migrate all stakers, as there is a window in which migration of staking is valid.

---

### YelayStaking
New staking contract, which inherits from `YelayStakingBase` (`SpoolStaking` before).  
`YelayStakingBase` is a simple Synthetix reward contract, with added functionality to mint `sYLAY` (`voSPOOL` before). `YelayStaking` inherits the same properties.
- `migrateUser`: migrate user stake from `SpoolStaking` to `YelayStaking`. Only callable by the `YelayMigrator` contract. _Note: This contract should also migrate SPOOL rewards from SpoolStaking and voSPOOL, as after SPOOL is paused they are not claimable. Currently, it gets SPOOL rewards from SpoolStaking only, as getting latest voSPOOL rewards earned is not possible via a view function. However, SpoolStaking and voSPOOLRewards are upgradeable, so it would be possible to add a function on SpoolStaking to get them, and upgrade SpoolStaking._

- `transferUser`: Allows a user to migrate their stake to another wallet (e.g. if they want to transfer from a hot wallet to a cold wallet). The new wallet must NOT be an existing staker.  
All other `SpoolStaking` functions stay in place.

---

### SYLAY
New staking power contract, which inherits from sYLAYBase (VoSPOOL before).

**TL;DR on voSPOOL:**
- Stakers earn 'voting power' by staking.
- Each stake accumulates voting power once a week ('tranche'), at a rate of 1/156 per week.
- Users may stake over many tranches, tranches mature independently.
- After 156 weeks from the tranche in which the stake occurred, the stake is 'fully matured,' i.e., voting power == stake amount.
- If users unstake, ALL voting power is burned, not just the amount which you unstake.
- Values are 'trimmed' to 48 bits, to pack several tranche amounts into 1 word in storage. For max 210m supply on SPOOL, trimming by 10**12 allows the full supply to fit into 48 bits.

It is intended that existing stakers and tranches will continue. As a result, we must migrate the existing state from the voSPOOL contract to the sYLAY contract.

sYLAY inherits voSPOOL, including all the same properties, over 208 weeks rather than 156 weeks. However, due to the supply difference between SPOOL and YELAY, we need to scale user stake amounts and voting power by the above ratio; the `ConversionLib` library handles this. Yelay supply is 1b, and so to fit the same value into 48 bits, we must trim by 10\**13. The conversion library first untrims the value (multiplication by 10\**12), scales to the Yelay amount, and then "retrims" using the Yelay trim value of 10\**13.

I've also added some new functions to voSPOOL(sYLAYBase now) to handle some edge cases due to the conversion:
- `_updateTotalRawUnmaturedVotingPower`
- `_updateTotalMaturingAmount`
- `_updateRawUnmaturedVotingPower`
- `_updateMaturingAmount`
Kostja added as well:
- `_updateTotalMaturedVotingPower`


The converted trimmed amount is not exactly the same as the stored amounts in user/global tranches, and these amounts are used when the indexes fully mature. This was leading to underflow issues. The above functions solve it by just setting the corresponding values to 0 if they are less than the stored amounts.

Functions in sYLAY:

- `migrateInitial`: prerequisite to start migration
- `migrateGlobalTranches`: allows the migrator contract to migrate global tranches from VoSPOOL to sYLAY. Performs conversion as above.
- `migrateUser`: allows the migrator contract to migrate user tranches and user global from VoSPOOL to sYLAY. Performs conversion as above.
- `transferUser`: allows the user, via the migrator contract, to transfer sYLAY state from one address to another.


# The Migration Flow

- Deploy YLAY, sYLAY, YelayStaking, sYLAYRewards, YelayMigrator, YelayRewardDistributor, YelayOwner (all upgradeable proxies)
- Upgrade SpoolStaking to SpoolStakingMigration to allow access amount of SPOOL rewards earned from voSPOOL
- Pause SPOOL token
- Most important part is migration of stakes which should be done by us at the start of the new epoch
to ensure we migrate all users during 1 week period
- Call `YelayMigrator.migrateInitial()`
- On sYLAY check that `sYLAY.migrationInitiated()` is true
- Call `YelayMigrator.migrateGlobalTranches(uint256)` for all indexes
- On sYLAY check that `sYLAY.globalMigrationComplete()` is true
- Call `YelayMigrator.migrateStake(address[])` for all stakers
- On sYLAY check that `sYLAY.migrationComplete()` is true
- On YelayStaking check that `YelayStaking.migrationComplete()` is true
- Users can migrate they balance on their own

TODO
- Arbitrum: migrator contract deployment, token deployment
- Deployment script

