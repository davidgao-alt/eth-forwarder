// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Forwarder
/// @notice Forwards any ETH and ERC20 it receives to `destination`, which the owner (admin) can change.
/// @dev ETH is forwarded automatically inside `receive()`. ERC20 transfers do not notify the recipient,
///      so tokens sit here until someone calls `flushToken` / `flushTokens`. Flushing is permissionless
///      because it can only ever send funds to the current `destination`.
contract Forwarder is Ownable2Step {
    using SafeERC20 for IERC20;

    address public destination;

    event DestinationChanged(address indexed previousDestination, address indexed newDestination);
    event ETHForwarded(address indexed from, address indexed to, uint256 amount);
    event TokenForwarded(address indexed token, address indexed to, uint256 amount);

    error InvalidDestination();
    error ETHForwardFailed();
    error RenounceDisabled();

    constructor(address initialOwner, address initialDestination) Ownable(initialOwner) {
        _setDestination(initialDestination);
    }

    /// @notice Plain ETH transfers are forwarded to `destination` in the same transaction.
    ///         If forwarding fails, the whole deposit reverts, so ETH never gets stuck here.
    receive() external payable {
        _sendETH(msg.value);
        emit ETHForwarded(msg.sender, destination, msg.value);
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    function setDestination(address newDestination) external onlyOwner {
        _setDestination(newDestination);
    }

    /// @dev Renouncing would freeze the destination forever; almost always a mistake.
    function renounceOwnership() public view override onlyOwner {
        revert RenounceDisabled();
    }

    // ---------------------------------------------------------------------
    // Flushing
    // ---------------------------------------------------------------------

    /// @notice Sends this contract's full balance of `token` to `destination`.
    function flushToken(address token) public {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) return;
        address to = destination;
        IERC20(token).safeTransfer(to, balance);
        emit TokenForwarded(token, to, balance);
    }

    function flushTokens(address[] calldata tokens) external {
        for (uint256 i; i < tokens.length; ++i) {
            flushToken(tokens[i]);
        }
    }

    /// @notice Sweeps ETH that arrived without triggering `receive()`
    ///         (e.g. SELFDESTRUCT, block rewards, or a pre-deployment send to this address).
    function flushETH() external {
        uint256 balance = address(this).balance;
        if (balance == 0) return;
        _sendETH(balance);
        emit ETHForwarded(address(this), destination, balance);
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _setDestination(address newDestination) private {
        // Forwarding to itself would recurse in receive() until out of gas.
        if (newDestination == address(0) || newDestination == address(this)) revert InvalidDestination();
        emit DestinationChanged(destination, newDestination);
        destination = newDestination;
    }

    function _sendETH(uint256 amount) private {
        (bool ok,) = destination.call{value: amount}("");
        if (!ok) revert ETHForwardFailed();
    }
}
