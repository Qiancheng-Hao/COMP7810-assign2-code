// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";

/// @title Ex2 + Ex4 — hands-on tasks: turn red into green
/// @notice Every `assertTrue(false, "TODO ...")` below is a placeholder. Write the real
///         assertion, watch the test go green, and that exercise is done.
///
///         Acceptance: make exercise (it should be red until you are finished)
///         Do not open test/Stablecoin.t.sol — it contains the answers. Write yours
///         first, and only look once you are stuck.
contract LoopTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));
    }

    // ==================================================================
    // Ex2 · the decimals trap: a 6-decimal stablecoin meets 18-decimal intuition
    // ==================================================================

    /// @dev For any legitimate amount x, totalSupply() must grow by exactly x after
    ///      deposit(x). Hint: use vm.assume to rule out x == 0, and faucet alice enough
    ///      usdc first.
    function test_Ex2_DepositIncreasesSupplyByExactly(uint96 raw) public {
        uint256 amount = uint256(raw) % 1_000_000e6;
        uint256 supplyBefore = stable.totalSupply();

        // Zero deposits are invalid; this property checks issuance for successful deposits.
        vm.assume(amount > 0);
        usdc.faucet(alice, amount);
        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        assertEq(stable.totalSupply() - supplyBefore, amount);
        assertEq(stable.balanceOf(alice), amount);
        assertEq(vault.totalCollateral(), amount);
    }

    /// @dev Run deposit with 1000e18 instead of 1000e6, see what happens, then assert what
    ///      you observed. MockUSDC has 6 decimals — 1000e18 is one billion USDC.
    ///      There is no expected answer here; the point is that you run it yourself and
    ///      read the numbers.
    function test_Ex2_DecimalsTrap() public {
        // With 6 decimals, this is 1e15 whole tokens: 1e12 times the intended 1,000.
        uint256 amount = 1000e18;

        usdc.faucet(alice, amount);
        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        // Read after minting: a local variable would retain the earlier balance if computed before deposit.
        uint256 actualTokens = stable.balanceOf(alice) / (uint256(10) ** stable.decimals());

        assertEq(usdc.decimals(), 6);
        assertEq(stable.decimals(), 6);
        assertEq(stable.balanceOf(alice), amount);
        assertEq(stable.totalSupply(), amount);
        assertEq(vault.totalCollateral(), stable.totalSupply());
        assertEq(actualTokens, 1e15);
        assertEq(actualTokens / 1000, 1e12);
    }

    // ==================================================================
    // Ex4 · permissions and pausing: where the guard is, who holds the key
    // ==================================================================

    /// @dev The attacker has no MINTER_ROLE, so calling mint directly must revert. Use
    ///      vm.expectRevert + abi.encodeWithSelector to pin down the exact error.
    function test_Ex4_Mint_RevertsForNonMinter() public {
        bytes32 minterRole = stable.MINTER_ROLE();
        assertFalse(stable.hasRole(minterRole, attacker));

        // Match the exact role error so an unrelated revert cannot make the test pass.
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, minterRole
            )
        );
        vm.prank(attacker);
        stable.mint(attacker, 1000e6);

        assertEq(stable.balanceOf(attacker), 0);
        assertEq(stable.totalSupply(), 0);
    }

    /// @dev After pause(), an ordinary transfer must revert
    function test_Ex4_Pause_BlocksTransfers() public {
        uint256 amount = 1000e6;

        // Fund Alice so this transfer would succeed if the token were not paused.
        stable.mint(alice, amount);
        stable.pause();
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(alice);
        stable.transfer(attacker, amount);

        assertEq(stable.balanceOf(alice), amount);
        assertEq(stable.balanceOf(attacker), 0);
        assertEq(stable.totalSupply(), amount);
    }

    /// @dev What pause() freezes is _update, so redemption is frozen along with everything
    ///      else — why is that bad news in a real crisis?
    ///      (This is STUDENT-QUESTIONS.md B1 and B2.)
    function test_Ex4_Pause_BlocksRedeem() public {

        // Establish a backed position so redemption fails because of pausing, not missing collateral.
        uint256 amount = 1000e6;

        usdc.faucet(alice, amount);
        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        stable.pause();
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(alice);
        vault.redeem(amount);

        assertEq(stable.balanceOf(alice), amount);
        assertEq(stable.totalSupply(), amount);
        assertEq(vault.totalCollateral(), amount);
        assertEq(usdc.balanceOf(alice), 0);
    }

    /// @dev An attacker cannot burn someone else's balance
    function test_Ex4_AttackerCannotBurnOthersBalance() public {
        uint256 amount = 1000e6;
        bytes32 minterRole = stable.MINTER_ROLE();

        // Give Alice a real balance so the rejected burn tests the attacker's missing permission.
        stable.mint(alice, amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, minterRole
            )
        );
        vm.prank(attacker);
        stable.burn(alice, amount);

        assertEq(stable.balanceOf(alice), amount);
        assertEq(stable.totalSupply(), amount);
    }

    /// @dev ...but the vault can, because it holds MINTER_ROLE and burn() answers to that
    ///      same role. This test proves the backdoor exists; it does not justify it.
    function test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance() public {
        uint256 amount = 1000e6;
        uint256 burnAmount = 400e6;

        usdc.faucet(alice, amount);
        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        assertTrue(stable.hasRole(stable.MINTER_ROLE(), address(vault)));
        
        // The USDC approval for deposit does not authorize the vault to burn Alice's sUSD.
        assertEq(stable.allowance(alice, address(vault)), 0);

        // Impersonation demonstrates role authority, not a public function to burn arbitrary users.
        vm.prank(address(vault));
        stable.burn(alice, burnAmount);

        assertEq(stable.balanceOf(alice), amount - burnAmount);
        assertEq(stable.totalSupply(), amount - burnAmount);
        assertEq(vault.totalCollateral(), amount);
        assertEq(usdc.balanceOf(alice), 0);
    }
}
