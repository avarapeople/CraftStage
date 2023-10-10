// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StableCookie
 * @author Sidoux
 */
contract StableCookie is ERC20Burnable, Ownable {
    error StableCookie__AmountMustBeMoreThanZero();
    error StableCookie__BurnAmountExceedsBalance();
    error StableCookie__NotZeroAddress();

    constructor() ERC20("StableCookie", "CKI") {}

    /**
     * @dev Burns a specific amount of tokens from the owner's account.
     * Can only be called by the owner.
     * @param _amount The amount of tokens to be burned.
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert StableCookie__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert StableCookie__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    /**
     * @dev Mints a specific amount of tokens and assigns them to an address.
     * Can only be called by the owner.
     * @param _to The address to which tokens will be minted.
     * @param _amount The amount of tokens to be minted.
     * @return A boolean indicating whether the minting was successful.
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert StableCookie__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert StableCookie__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
