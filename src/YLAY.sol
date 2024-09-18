// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IYLAY.sol";
import "./interfaces/IYelayMigrator.sol";
import "spool-core/SpoolOwnable.sol";

contract YLAY is IYLAY, SpoolOwnable, Initializable, ERC20PausableUpgradeable, UUPSUpgradeable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000e18;

    IYelayMigrator public immutable migrator;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(ISpoolOwner _spoolOwner, IYelayMigrator _migrator) SpoolOwnable(_spoolOwner) initializer {
        migrator = _migrator;
    }

    function initialize() public initializer {
        __ERC20_init("Yelay Token", "YLAY");
        __ERC20Pausable_init();
        __UUPSUpgradeable_init();
        // Mint all tokens to the contract address
        _mint(address(this), MAX_SUPPLY);
    }

    // Allow the migrator or admin to transfer minted tokens to a claimant
    function claim(address claimant, uint256 amount) external {
        require(address(migrator) == _msgSender() || isSpoolOwner(), "YLAY::claim: Caller is not the migrator or admin");
        _transfer(address(this), claimant, amount);
    }

    // Admin can pause the contract
    function pause() external onlyOwner {
        _pause();
    }

    // Admin can unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }

    // Upgrade authorization, restricted to the admin
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
