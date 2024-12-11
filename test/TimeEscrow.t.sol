// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "solmate/test/utils/mocks/MockERC20.sol";
import "../src/interfaces/ITimeEscrow.sol";

contract TimeEscrowTest is Test {
    address public RECEIVER = address(0x1);
    ITimeEscrow public timeEscrow;
    MockERC20 public token;

    function setUp() public {
        //        timeEscrow = new TimeEscrow();
        token = new MockERC20("Mock", "MOCK", 18);
        token.mint(address(this), 1e24);
        token.approve(address(timeEscrow), type(uint256).max);
        vm.deal(address(this), 1e24);
    }

    function testLock() public {
        assertFalse(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0))
        );
        assertFalse(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 1))
        );

        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Locked(address(this), RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0);
        timeEscrow.lock(RECEIVER, address(token), 1e18, block.timestamp + 1 days);

        assertEq(token.balanceOf(address(this)), 1e24 - 1e18);
        assertEq(token.balanceOf(address(timeEscrow)), 1e18);
        assertTrue(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0))
        );
        assertFalse(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 1))
        );
    }

    function testLockNative() public {
        assertFalse(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0))
        );
        assertFalse(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 1))
        );

        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Locked(address(this), RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0);
        timeEscrow.lock{value: 1e18}(RECEIVER, address(0), 1e18, block.timestamp + 1 days);

        assertEq(address(this).balance, 1e24 - 1e18);
        assertEq(address(timeEscrow).balance, 1e18);
        assertTrue(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0))
        );
        assertFalse(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 1))
        );
    }

    function testLockNativeWithInaccurateValue() public {
        vm.expectRevert(abi.encodeWithSelector(ITimeEscrow.InvalidValue.selector));
        timeEscrow.lock{value: 1e18 - 1}(RECEIVER, address(0), 1e18, block.timestamp + 1 days);

        vm.expectRevert(abi.encodeWithSelector(ITimeEscrow.InvalidValue.selector));
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
        emit ITimeEscrow.Unlocked(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0);
        timeEscrow.unlock(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0));

        assertEq(token.balanceOf(address(this)), 1e24 - 1e18);
        assertEq(token.balanceOf(RECEIVER), 1e18);
        assertEq(token.balanceOf(address(timeEscrow)), 0);
        assertFalse(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0))
        );
    }

    function testUnlockWithInvalidParams() public {
        timeEscrow.lock(RECEIVER, address(token), 1e18, block.timestamp + 1 days);

        vm.warp(block.timestamp + 1 days);

        uint256 beforeThisBalance = token.balanceOf(address(this));
        uint256 beforeReceiverBalance = token.balanceOf(RECEIVER);
        uint256 beforeTimeEscrowBalance = token.balanceOf(address(timeEscrow));

        assertFalse(
            timeEscrow.unlock(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 1))
        );
        assertEq(token.balanceOf(address(this)), beforeThisBalance);
        assertEq(token.balanceOf(RECEIVER), beforeReceiverBalance);
        assertEq(token.balanceOf(address(timeEscrow)), beforeTimeEscrowBalance);
        assertTrue(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0))
        );

        assertFalse(
            timeEscrow.unlock(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days - 1, 0))
        );
        assertEq(token.balanceOf(address(this)), beforeThisBalance);
        assertEq(token.balanceOf(RECEIVER), beforeReceiverBalance);
        assertEq(token.balanceOf(address(timeEscrow)), beforeTimeEscrowBalance);
        assertTrue(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0))
        );

        assertFalse(
            timeEscrow.unlock(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18 + 1, block.timestamp + 1 days, 0))
        );
        assertEq(token.balanceOf(address(this)), beforeThisBalance);
        assertEq(token.balanceOf(RECEIVER), beforeReceiverBalance);
        assertEq(token.balanceOf(address(timeEscrow)), beforeTimeEscrowBalance);
        assertTrue(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0))
        );
    }

    function testUnlockBeforeTime() public {
        timeEscrow.lock(RECEIVER, address(token), 1e18, block.timestamp + 1 days);

        uint256 beforeThisBalance = token.balanceOf(address(this));
        uint256 beforeReceiverBalance = token.balanceOf(RECEIVER);
        uint256 beforeTimeEscrowBalance = token.balanceOf(address(timeEscrow));

        vm.warp(block.timestamp + 1 days - 1);

        assertFalse(
            timeEscrow.unlock(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0))
        );
        assertEq(token.balanceOf(address(this)), beforeThisBalance);
        assertEq(token.balanceOf(RECEIVER), beforeReceiverBalance);
        assertEq(token.balanceOf(address(timeEscrow)), beforeTimeEscrowBalance);
        assertTrue(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0))
        );
    }

    function testUnlockEth() public {
        timeEscrow.lock{value: 1e18}(RECEIVER, address(0), 1e18, block.timestamp + 1 days);

        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Unlocked(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0);
        timeEscrow.unlock(ITimeEscrow.UnlockParams(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0));

        assertEq(address(this).balance, 1e24 - 1e18);
        assertEq(address(RECEIVER).balance, 1e18);
        assertEq(address(timeEscrow).balance, 0);
        assertFalse(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0))
        );
    }

    function testUnlockAll() public {
        timeEscrow.lock(RECEIVER, address(token), 1e18, block.timestamp + 1 days);
        timeEscrow.lock(RECEIVER, address(token), 1e18, block.timestamp + 1 days);
        timeEscrow.lock{value: 1e18}(RECEIVER, address(0), 1e18, block.timestamp + 1 days);

        vm.warp(block.timestamp + 1 days);

        ITimeEscrow.UnlockParams[] memory params = new ITimeEscrow.UnlockParams[](3);
        params[0] = ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0);
        params[1] = ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 1);
        params[2] = ITimeEscrow.UnlockParams(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0);

        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Unlocked(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0);
        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Unlocked(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 1);
        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Unlocked(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0);
        bool[] memory results = timeEscrow.unlockAll(params);

        for (uint256 i = 0; i < params.length; ++i) {
            assertEq(results[i], true);
        }
        assertEq(token.balanceOf(address(this)), 1e24 - 2e18);
        assertEq(token.balanceOf(RECEIVER), 2e18);
        assertEq(token.balanceOf(address(timeEscrow)), 0);
        assertEq(address(this).balance, 1e24 - 1e18);
        assertEq(address(RECEIVER).balance, 1e18);
        assertEq(address(timeEscrow).balance, 0);
        assertFalse(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0))
        );
        assertFalse(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 1))
        );
        assertFalse(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0))
        );
    }

    function testUnlockAllWithSomeInvalidParams() public {
        timeEscrow.lock(RECEIVER, address(token), 1e18, block.timestamp + 1 days);
        timeEscrow.lock(RECEIVER, address(token), 1e18, block.timestamp + 1 days);
        timeEscrow.lock{value: 1e18}(RECEIVER, address(0), 1e18, block.timestamp + 1 days);

        vm.warp(block.timestamp + 1 days);

        ITimeEscrow.UnlockParams[] memory params = new ITimeEscrow.UnlockParams[](4);
        params[0] = ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 123);
        params[1] = ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 1);
        params[2] = ITimeEscrow.UnlockParams(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0);
        params[3] = ITimeEscrow.UnlockParams(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0);

        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Unlocked(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 1);
        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Unlocked(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0);
        bool[] memory results = timeEscrow.unlockAll(params);

        assertFalse(results[0]);
        assertTrue(results[1]);
        assertTrue(results[2]);
        assertFalse(results[3]);
        assertEq(token.balanceOf(address(this)), 1e24 - 1e18);
        assertEq(token.balanceOf(RECEIVER), 1e18);
        assertEq(token.balanceOf(address(timeEscrow)), 1e18);
        assertEq(address(this).balance, 1e24 - 1e18);
        assertEq(address(RECEIVER).balance, 1e18);
        assertEq(address(timeEscrow).balance, 0);
        assertTrue(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 0))
        );
        assertFalse(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(token), 1e18, block.timestamp + 1 days, 1))
        );
        assertFalse(
            timeEscrow.isEscrowed(ITimeEscrow.UnlockParams(RECEIVER, address(0), 1e18, block.timestamp + 1 days, 0))
        );
    }
}
