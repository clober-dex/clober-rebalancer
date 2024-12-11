// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "solmate/test/utils/mocks/MockERC20.sol";

import "../src/TimeEscrow.sol";
import "../src/interfaces/ITimeEscrow.sol";

import "forge-std/Test.sol";

contract TimeEscrowTest is Test {
    address public RECEIVER = address(0x1);
    ITimeEscrow public timeEscrow;
    MockERC20 public token;

    bool public blocked;

    function setUp() public {
        address timeEscrowTemplate = address(new TimeEscrow());
        timeEscrow = ITimeEscrow(
            address(
                new ERC1967Proxy(
                    timeEscrowTemplate, abi.encodeWithSelector(TimeEscrow.initialize.selector, address(this))
                )
            )
        );
        token = new MockERC20("Mock", "MOCK", 18);
        token.mint(address(this), 1e24);
        token.approve(address(timeEscrow), type(uint256).max);
        vm.deal(address(this), 1e24);
    }

    function testLock() public {
        assertFalse(timeEscrow.isEscrowed(0));
        assertFalse(timeEscrow.isEscrowed(1));
        assertEq(timeEscrow.escrowCounts(), 0);

        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Lock(address(this), RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0);
        timeEscrow.lock(RECEIVER, address(token), 1e18, block.timestamp + 1 days);

        assertEq(token.balanceOf(address(this)), 1e24 - 1e18);
        assertEq(token.balanceOf(address(timeEscrow)), 1e18);
        assertTrue(timeEscrow.isEscrowed(0));
        assertFalse(timeEscrow.isEscrowed(1));
        assertEq(timeEscrow.escrowCounts(), 1);
        assertEq(
            timeEscrow.getProof(0), keccak256(abi.encode(RECEIVER, address(token), 1e18, block.timestamp + 1 days))
        );
    }

    function testLockNative() public {
        assertFalse(timeEscrow.isEscrowed(0));
        assertFalse(timeEscrow.isEscrowed(1));
        assertEq(timeEscrow.escrowCounts(), 0);

        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Lock(address(this), RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0);
        timeEscrow.lock{value: 1e18}(RECEIVER, address(0), 1e18, block.timestamp + 1 days);

        assertEq(address(this).balance, 1e24 - 1e18);
        assertEq(address(timeEscrow).balance, 1e18);
        assertTrue(timeEscrow.isEscrowed(0));
        assertFalse(timeEscrow.isEscrowed(1));
        assertEq(timeEscrow.escrowCounts(), 1);
        assertEq(timeEscrow.getProof(0), keccak256(abi.encode(RECEIVER, address(0), 1e18, block.timestamp + 1 days)));
    }

    function testLockMultiple() public {
        timeEscrow.lock(RECEIVER, address(token), 1e18, block.timestamp + 1 days);
        timeEscrow.lock(RECEIVER, address(token), 1e18, block.timestamp + 1 days);
        timeEscrow.lock{value: 1e18}(RECEIVER, address(0), 1e18, block.timestamp + 1 days);

        assertEq(token.balanceOf(address(this)), 1e24 - 2e18);
        assertEq(token.balanceOf(address(timeEscrow)), 2e18);
        assertEq(address(this).balance, 1e24 - 1e18);
        assertEq(address(timeEscrow).balance, 1e18);
        assertTrue(timeEscrow.isEscrowed(0));
        assertTrue(timeEscrow.isEscrowed(1));
        assertTrue(timeEscrow.isEscrowed(2));
        assertEq(timeEscrow.escrowCounts(), 3);
    }

    function testLockWithZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(ITimeEscrow.InvalidAmount.selector));
        timeEscrow.lock(RECEIVER, address(token), 0, block.timestamp + 1 days);

        vm.expectRevert(abi.encodeWithSelector(ITimeEscrow.InvalidAmount.selector));
        timeEscrow.lock{value: 0}(RECEIVER, address(0), 0, block.timestamp + 1 days);
    }

    function testLockNativeWithInaccurateValue() public {
        vm.expectRevert(abi.encodeWithSelector(ITimeEscrow.InvalidAmount.selector));
        timeEscrow.lock{value: 1e18 - 1}(RECEIVER, address(0), 1e18, block.timestamp + 1 days);

        vm.expectRevert(abi.encodeWithSelector(ITimeEscrow.InvalidAmount.selector));
        timeEscrow.lock{value: 1e18 + 1}(RECEIVER, address(0), 1e18, block.timestamp + 1 days);
    }

    function testValueTransfer() public {
        (bool success,) = address(timeEscrow).call{value: 1e18}("");
        assertFalse(success);
    }

    function testUnlock() public {
        timeEscrow.lock(RECEIVER, address(token), 1e18, block.timestamp + 1 days);

        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Unlock(RECEIVER, address(token), 1e18, block.timestamp, 0);
        timeEscrow.unlock(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp, 0));

        assertEq(token.balanceOf(address(this)), 1e24 - 1e18);
        assertEq(token.balanceOf(RECEIVER), 1e18);
        assertEq(token.balanceOf(address(timeEscrow)), 0);
        assertFalse(timeEscrow.isEscrowed(0));
    }

    function testUnlockWithInvalidParams() public {
        timeEscrow.lock(RECEIVER, address(token), 1e18, block.timestamp + 1 days);

        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(abi.encodeWithSelector(ITimeEscrow.InvalidProof.selector));
        timeEscrow.unlock(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp, 1));

        vm.expectRevert(abi.encodeWithSelector(ITimeEscrow.InvalidProof.selector));
        timeEscrow.unlock(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp - 1, 0));

        vm.expectRevert(abi.encodeWithSelector(ITimeEscrow.InvalidProof.selector));
        timeEscrow.unlock(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18 + 1, block.timestamp, 0));
    }

    function testUnlockBeforeTime() public {
        uint256 unlock = block.timestamp + 1 days;
        timeEscrow.lock(RECEIVER, address(token), 1e18, unlock);

        vm.warp(unlock - 1);

        vm.expectRevert(abi.encodeWithSelector(ITimeEscrow.Locked.selector));
        timeEscrow.unlock(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, unlock, 0));
    }

    function testUnlockEth() public {
        timeEscrow.lock{value: 1e18}(RECEIVER, address(0), 1e18, block.timestamp + 1 days);

        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Unlock(RECEIVER, address(0), 1e18, block.timestamp, 0);
        timeEscrow.unlock(ITimeEscrow.UnlockParams(RECEIVER, address(0), 1e18, block.timestamp, 0));

        assertEq(address(this).balance, 1e24 - 1e18);
        assertEq(address(RECEIVER).balance, 1e18);
        assertEq(address(timeEscrow).balance, 0);
        assertFalse(timeEscrow.isEscrowed(0));
    }

    function testUnlockEthWhenReceiverFails() public {
        timeEscrow.lock{value: 1e18}(address(this), address(0), 1e18, block.timestamp + 1 days);

        blocked = true;
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(abi.encodeWithSelector(ITimeEscrow.ValueTransferFailed.selector));
        timeEscrow.unlock(ITimeEscrow.UnlockParams(address(this), address(0), 1e18, block.timestamp, 0));
    }

    receive() external payable {
        require(!blocked, "Blocked");
    }
}
