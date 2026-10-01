// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SlateTestDollar (TESTUSD)
/// @notice Testnet stand-in for Paxos USDG. Not USDG.
/// @dev Exists only because no USDG on Robinhood Chain testnet can be minted at the volumes needed to seed pools
///      at real stock prices. It has no value and no peg. On mainnet Slate uses Paxos USDG itself
///      (0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168 on Robinhood Chain). 6 decimals, like USDG.
contract SlateTestDollar is ERC20, Ownable {
    uint256 public constant FAUCET_AMOUNT = 10_000e6;
    uint256 public constant FAUCET_COOLDOWN = 1 days;

    mapping(address account => uint256) public lastFaucetAt;

    event Faucet(address indexed to, uint256 amount);

    error FaucetCooldown(uint256 nextAt);

    constructor(address owner_) ERC20("Slate Test Dollar", "TESTUSD") Ownable(owner_) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Sends `FAUCET_AMOUNT` to the caller, once per `FAUCET_COOLDOWN`.
    function faucet() external {
        uint256 last = lastFaucetAt[msg.sender];
        if (last != 0 && block.timestamp < last + FAUCET_COOLDOWN) revert FaucetCooldown(last + FAUCET_COOLDOWN);
        lastFaucetAt[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
        emit Faucet(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Owner mint, for seeding testnet liquidity.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
