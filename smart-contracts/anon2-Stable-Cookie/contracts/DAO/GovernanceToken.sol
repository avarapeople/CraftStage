// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20, ERC20Permit, ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/**
 * @title GovernanceToken
 * @author Sidoux
 * @dev A Solidity contract representing a governance token with voting capabilities.
 * This token extends ERC20Votes from the OpenZeppelin library to provide voting features.
 * - Before making a proposal, a snapshot is taken to gent the tokens user's balance at a specific time.
 *    So we avoid people to buy and dump the token. to do so, we use ERC20Vote.
 *    ERC20Vote have a checkpoint function which help getting snapshot of the balances at a certain moment.
 */
contract GovernanceToken is ERC20Votes {
    uint256 public s_maxSupply = 1000000 ether;

    constructor() ERC20("GovernanceToken", "GT") ERC20Permit("GovernanceToken") {
        _mint(msg.sender, s_maxSupply);
    }

    /**
     * @dev Overrides the internal function _afterTokenTransfer to update the snapshots after token transfers.
     * @param from The address from which tokens are transferred.
     * @param to The address to which tokens are transferred.
     * @param amount The amount of tokens transferred.
     */
    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    /**
     * @dev Overrides the internal function _mint to update the voting snapshots after minting tokens.
     * @param to The address to which tokens are minted.
     * @param amount The amount of tokens minted.
     */
    function _mint(address to, uint256 amount) internal override(ERC20Votes) {
        super._mint(to, amount);
    }

    /**
     * @dev Overrides the internal function _burn to update the voting snapshots after burning tokens.
     * @param account The address from which tokens are burned.
     * @param amount The amount of tokens burned.
     */
    function _burn(address account, uint256 amount) internal override(ERC20Votes) {
        super._burn(account, amount);
    }
}
