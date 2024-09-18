// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IYLAY.sol";
import "./interfaces/IYelayMigrator.sol";
import "./YelayOwnable.sol";

contract YLAY is IYLAY, YelayOwnable, Initializable, ERC20PausableUpgradeable, UUPSUpgradeable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000e18;

    IYelayMigrator public immutable migrator;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IYelayOwner _yelayOwner, IYelayMigrator _migrator) YelayOwnable(_yelayOwner) initializer {
        migrator = _migrator;
    }

    function initialize() public initializer {
        __ERC20_init("Yelay Token", "YLAY");
        __ERC20Pausable_init();
        __UUPSUpgradeable_init();
        // Mint all tokens to the contract address
        _mint(address(this), MAX_SUPPLY);
    }

    /**
     * @notice Allow the migrator or admin to transfer minted tokens to a claimant
     * @param claimant address
     * @param amount to transfer
     */
    function claim(address claimant, uint256 amount) external {
        require(address(migrator) == _msgSender() || isYelayOwner(), "YLAY::claim: Caller is not the migrator or admin");
        _transfer(address(this), claimant, amount);
    }

    /**
     * @dev Owner can pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Owner can unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Upgrade authorization, restricted to the owner
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
