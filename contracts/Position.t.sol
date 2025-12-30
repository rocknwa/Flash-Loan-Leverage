// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Position} from "./Position.sol";
import {Test, console} from "forge-std/Test.sol";

// Solidity tests are compatible with foundry, so they
// use the same syntax and offer the same functionality.

contract PositionTest is Test {
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    Position position;
    address owner;
    address attacker;

    receive() external payable {}

    fallback() external payable {}

    function setUp() public {
        position = new Position();
        owner = address(this);
        attacker = address(0x1);
    }

    function test_Owner() public view {
        require(position.owner() == owner, "Owner does not match");
    }

    function test_WithdrawETH() public {
        uint256 amount = 1 ether;

        // Send some ETH to the contract
        vm.deal(address(position), amount);

        uint256 ownerBalanceBefore = owner.balance;

        // Withdraw the ETH
        position.withdrawETH();

        uint256 ownerBalanceAfter = owner.balance;
        uint256 positionBalanceAfter = address(position).balance;

        // Check that the balances updated
        require(
            ownerBalanceBefore + amount == ownerBalanceAfter,
            "Owner's balance did not increase"
        );

        require(positionBalanceAfter == 0, "Position balance does not equal 0");
    }

    function test_OnlyOwnerCanOpenPosition() public {
        Position.OpenParams memory params = Position.OpenParams(
            address(0xA),
            address(0xB),
            1 ether,
            1 ether,
            0
        );

        vm.prank(attacker);
        vm.expectRevert("Position: Caller not owner");
        position.openPosition(params);
    }

    function test_OnlyOwnerCanClosePosition() public {
        Position.CloseParams memory params = Position.CloseParams(
            address(0xA),
            address(0xB)
        );

        vm.prank(attacker);
        vm.expectRevert("Position: Caller not owner");
        position.closePosition(params);
    }

    function test_OnlyBalancerCanCallReceiveFlashLoan() public {
        // We'll have to setup the parameters as if Balancer called us
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(WETH_ADDRESS);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        uint256[] memory feeAmounts = new uint256[](1);
        feeAmounts[0] = 0;

        // Encode some dummy params
        bytes memory params = abi.encode(address(0xA), address(0xB));

        vm.prank(attacker);
        vm.expectRevert("Position: Caller not Balancer Vault");
        position.receiveFlashLoan(tokens, amounts, feeAmounts, params);
    }

    function test_OnlyOwnerCanCallWithdrawETH() public {
        vm.deal(address(position), 1 ether);
        vm.prank(attacker);
        vm.expectRevert("Position: Caller not owner");
        position.withdrawETH();
    }

    function test_OnlyOwnerCanCallWithdrawTokens() public {
        vm.prank(attacker);
        vm.expectRevert("Position: Caller not owner");
        position.withdrawTokens(WETH_ADDRESS, 1 ether);
    }
}
