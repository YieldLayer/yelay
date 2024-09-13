// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IYLAY.sol";
import "./interfaces/IYelayMigrator.sol";
import "spool-core/SpoolOwnable.sol";

contract YLAY is
    IYLAY,
    SpoolOwnable,
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    UUPSUpgradeable
{
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    IYelayMigrator public migrator;

    constructor(ISpoolOwner _spoolOwner) SpoolOwnable(_spoolOwner) {}

    function initialize(IYelayMigrator _migrator) public initializer {
        __ERC20_init("Yelay Token", "YLAY");
        __ERC20Pausable_init();
        __UUPSUpgradeable_init();

        migrator = _migrator;

        // Mint all tokens to the contract address
        _mint(address(this), MAX_SUPPLY);
    }

    // Allow the migrator or admin to transfer minted tokens to a claimant
    function claim(address claimant, uint256 amount) external onlyMigratorOrAdmin {
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

    // Override the _beforeTokenTransfer to include pause functionality
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        super._beforeTokenTransfer(from, to, amount); // Call the parent hooks
    }

    // Upgrade authorization, restricted to the admin
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    modifier onlyMigratorOrAdmin() {
        _onlyMigratorOrAdmin();
        _;
    }

    function _onlyMigratorOrAdmin() internal view {
        require(address(migrator) == _msgSender() || isSpoolOwner(), "YLAY::_onlyMigratorOrAdmin: Caller is not the migrator or admin");
    }
}
