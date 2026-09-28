// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Forwarder} from "../src/Forwarder.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Mimics USDT: transfer() returns nothing instead of bool.
contract NoReturnToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }
}

contract RejectingReceiver {
    receive() external payable {
        revert("no");
    }
}

contract ForwarderTest is Test {
    Forwarder fwd;
    address owner = makeAddr("owner");
    address dest = makeAddr("dest");
    address user = makeAddr("user");

    function setUp() public {
        fwd = new Forwarder(owner, dest);
        vm.deal(user, 100 ether);
    }

    function test_constructor() public view {
        assertEq(fwd.owner(), owner);
        assertEq(fwd.destination(), dest);
    }

    function test_constructor_rejectsZeroDestination() public {
        vm.expectRevert(Forwarder.InvalidDestination.selector);
        new Forwarder(owner, address(0));
    }

    function testFuzz_ethIsForwardedImmediately(uint256 amount) public {
        amount = bound(amount, 0, user.balance);
        vm.prank(user);
        (bool ok,) = address(fwd).call{value: amount}("");
        assertTrue(ok);
        assertEq(dest.balance, amount);
        assertEq(address(fwd).balance, 0);
    }

    function test_ethDepositRevertsIfDestinationRejects() public {
        RejectingReceiver r = new RejectingReceiver();
        vm.prank(owner);
        fwd.setDestination(address(r));

        vm.prank(user);
        (bool ok,) = address(fwd).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(user.balance, 100 ether);
    }

    function test_ethWithCalldataReverts() public {
        vm.prank(user);
        (bool ok,) = address(fwd).call{value: 1 ether}(hex"deadbeef");
        assertFalse(ok);
    }

    function testFuzz_flushToken(uint256 amount) public {
        MockToken t = new MockToken();
        t.mint(address(fwd), amount);

        vm.prank(user); // anyone may flush
        fwd.flushToken(address(t));

        assertEq(t.balanceOf(dest), amount);
        assertEq(t.balanceOf(address(fwd)), 0);
    }

    function test_flushToken_emitsEvent() public {
        MockToken t = new MockToken();
        t.mint(address(fwd), 42);

        vm.expectEmit(address(fwd));
        emit Forwarder.TokenForwarded(address(t), dest, 42);
        fwd.flushToken(address(t));
    }

    function test_ethDeposit_emitsEvent() public {
        vm.expectEmit(address(fwd));
        emit Forwarder.ETHForwarded(user, dest, 1 ether);
        vm.prank(user);
        (bool ok,) = address(fwd).call{value: 1 ether}("");
        assertTrue(ok);
    }

    function test_setDestination_emitsEvent() public {
        address newDest = makeAddr("newDest");
        vm.expectEmit(address(fwd));
        emit Forwarder.DestinationChanged(dest, newDest);
        vm.prank(owner);
        fwd.setDestination(newDest);
    }

    function test_flushToken_usdtStyle() public {
        NoReturnToken t = new NoReturnToken();
        t.mint(address(fwd), 1_000e6);
        fwd.flushToken(address(t));
        assertEq(t.balanceOf(dest), 1_000e6);
    }

    function test_flushTokens_batch() public {
        MockToken a = new MockToken();
        MockToken b = new MockToken();
        a.mint(address(fwd), 5);
        b.mint(address(fwd), 7);

        address[] memory list = new address[](2);
        list[0] = address(a);
        list[1] = address(b);
        fwd.flushTokens(list);

        assertEq(a.balanceOf(dest), 5);
        assertEq(b.balanceOf(dest), 7);
    }

    function test_flushETH_sweepsForcedETH() public {
        vm.deal(address(fwd), 3 ether); // simulates SELFDESTRUCT / pre-funded address
        fwd.flushETH();
        assertEq(dest.balance, 3 ether);
    }

    function test_setDestination_onlyOwner() public {
        address newDest = makeAddr("newDest");

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        fwd.setDestination(newDest);

        vm.prank(owner);
        fwd.setDestination(newDest);
        assertEq(fwd.destination(), newDest);

        vm.prank(user);
        (bool ok,) = address(fwd).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(newDest.balance, 1 ether);
    }

    function test_setDestination_rejectsZeroAndSelf() public {
        vm.startPrank(owner);
        vm.expectRevert(Forwarder.InvalidDestination.selector);
        fwd.setDestination(address(0));
        vm.expectRevert(Forwarder.InvalidDestination.selector);
        fwd.setDestination(address(fwd));
        vm.stopPrank();
    }

    function test_ownershipTransferIsTwoStep() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        fwd.transferOwnership(newOwner);
        assertEq(fwd.owner(), owner); // not yet

        vm.prank(newOwner);
        fwd.acceptOwnership();
        assertEq(fwd.owner(), newOwner);
    }

    function test_renounceDisabled() public {
        vm.prank(owner);
        vm.expectRevert(Forwarder.RenounceDisabled.selector);
        fwd.renounceOwnership();
    }
}
