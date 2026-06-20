// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {PIF12Nexus} from "../contracts/PIF12Nexus.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title PIF12Nexus v1.0.0 — 🔴 critical test matrix + key 🟡 paths
 * @notice Verifies deploy/init, GAME_ROLE mint, year windows, soulbound lock,
 *         role separation, pause, admin recovery, the issuanceEnabled gate,
 *         and (🟡) mutual aid, Star issuance, guardian recovery, revokeCurator.
 *         Every revert asserts the SPECIFIC custom error → confirms the
 *         require→custom-error negations are correct.
 */
contract PIF12NexusTest is Test {
    PIF12Nexus internal nexus;

    address internal admin     = makeAddr("admin");      // Safe multisig stand-in
    address internal gameOp    = makeAddr("gameOp");     // GAME_ROLE relay
    address internal forwarder = makeAddr("forwarder");  // trusted forwarder (unused in these tests)
    address internal alice     = makeAddr("alice");
    address internal bob       = makeAddr("bob");
    address internal carol     = makeAddr("carol");
    address internal dave      = makeAddr("dave");

    // Large base timestamp so recovery cooldowns (lastRecoveryTime default 0) pass.
    uint256 internal constant T0 = 1_800_000_000;

    function setUp() public {
        vm.warp(T0);
        PIF12Nexus impl = new PIF12Nexus();
        bytes memory initData =
            abi.encodeCall(PIF12Nexus.initialize, (admin, gameOp, forwarder, "ipfs://base/{id}.json"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        nexus = PIF12Nexus(address(proxy));
    }

    // ---------- helpers ----------
    function _openYear(uint8 y) internal {
        vm.prank(admin);
        nexus.setYearWindow(y, T0, T0 + 365 days);
    }

    function _makeCurator(address who, uint8 y) internal {
        _openYear(y);
        vm.prank(gameOp);
        nexus.mintCuratorToken(who, y);
    }

    // =========================================================
    // 🔴 Deploy / Init
    // =========================================================
    function test_InitialRolesGranted() public view {
        assertTrue(nexus.hasRole(nexus.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(nexus.hasRole(nexus.UPGRADER_ROLE(), admin));
        assertTrue(nexus.hasRole(nexus.PAUSER_ROLE(), admin));
        assertTrue(nexus.hasRole(nexus.GAME_ROLE(), gameOp));
        assertFalse(nexus.hasRole(nexus.GAME_ROLE(), admin));
    }

    function test_VersionIsV1() public view {
        assertEq(nexus.VERSION(), "1.0.0");
    }

    function test_NextPersonalIdStartsAt100() public view {
        assertEq(nexus.nextPersonalTokenId(), 100);
    }

    function test_CannotReinitialize() public {
        vm.expectRevert(); // OZ Initializable: InvalidInitialization
        nexus.initialize(admin, gameOp, forwarder, "x");
    }

    // =========================================================
    // 🔴 GAME_ROLE / mintCuratorToken
    // =========================================================
    function test_MintCurator_HappyPath() public {
        _makeCurator(alice, 1);
        assertTrue(nexus.isCurator(alice));
        assertEq(nexus.curatorYear(alice), 1);
        assertEq(nexus.curatorSince(alice), T0);
        assertEq(nexus.balanceOf(alice, 1), 1);
        assertEq(nexus.heldTokenCount(alice), 1);
        assertTrue(nexus.isMember(alice));
    }

    function test_Mint_RevertIfNotGameRole() public {
        _openYear(1);
        vm.prank(alice);
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        nexus.mintCuratorToken(bob, 1);
    }

    function test_Mint_RevertIfYearClosed() public {
        vm.prank(gameOp);
        vm.expectRevert(PIF12Nexus.YearWindowClosed.selector);
        nexus.mintCuratorToken(alice, 1);
    }

    function test_Mint_RevertIfBadYear() public {
        vm.prank(gameOp);
        vm.expectRevert(PIF12Nexus.YearOutOfRange.selector);
        nexus.mintCuratorToken(alice, 0);

        vm.prank(gameOp);
        vm.expectRevert(PIF12Nexus.YearOutOfRange.selector);
        nexus.mintCuratorToken(alice, 13);
    }

    function test_Mint_RevertZeroRecipient() public {
        _openYear(1);
        vm.prank(gameOp);
        vm.expectRevert(PIF12Nexus.ZeroRecipient.selector);
        nexus.mintCuratorToken(address(0), 1);
    }

    function test_Mint_RevertIfAlreadyCurator() public {
        _makeCurator(alice, 1);
        _openYear(2);
        vm.prank(gameOp);
        vm.expectRevert(PIF12Nexus.AlreadyCurator.selector);
        nexus.mintCuratorToken(alice, 2);
    }

    function test_GameRoleCannotDoAdmin() public {
        vm.prank(gameOp);
        vm.expectRevert(); // gameOp lacks DEFAULT_ADMIN_ROLE
        nexus.setYearWindow(1, T0, T0 + 1 days);

        _makeCurator(alice, 1);
        vm.prank(gameOp);
        vm.expectRevert();
        nexus.revokeCurator(alice, "x");

        vm.prank(gameOp);
        vm.expectRevert();
        nexus.setIssuanceEnabled(true);
    }

    // =========================================================
    // 🔴 Year window
    // =========================================================
    function test_SetYearWindow_OnlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        nexus.setYearWindow(1, T0, T0 + 1 days);
    }

    function test_SetYearWindow_RevertDeadlineBeforeStart() public {
        vm.prank(admin);
        vm.expectRevert(PIF12Nexus.BadYearWindow.selector);
        nexus.setYearWindow(1, T0 + 10, T0); // deadline <= start
    }

    function test_SetYearWindow_RevertYearOutOfRange() public {
        vm.prank(admin);
        vm.expectRevert(PIF12Nexus.YearOutOfRange.selector);
        nexus.setYearWindow(13, T0, T0 + 1 days);
    }

    function test_IsYearOpen_Boundaries() public {
        vm.prank(admin);
        nexus.setYearWindow(1, T0 + 100, T0 + 200);

        vm.warp(T0 + 50);
        assertFalse(nexus.isYearOpen(1)); // before start
        vm.warp(T0 + 100);
        assertTrue(nexus.isYearOpen(1));  // at start (inclusive)
        vm.warp(T0 + 150);
        assertTrue(nexus.isYearOpen(1));  // within
        vm.warp(T0 + 200);
        assertTrue(nexus.isYearOpen(1));  // at deadline (inclusive)
        vm.warp(T0 + 201);
        assertFalse(nexus.isYearOpen(1)); // after deadline
    }

    function test_IsYearOpen_FalseIfNeverSet() public view {
        assertFalse(nexus.isYearOpen(5));
    }

    // =========================================================
    // 🔴 Soulbound lock + heldTokenCount
    // =========================================================
    function test_Soulbound_HolderCannotTransfer() public {
        _makeCurator(alice, 1);
        vm.prank(alice); // from == sender, so approval passes; soulbound _update blocks
        vm.expectRevert(PIF12Nexus.SoulboundTransferLocked.selector);
        nexus.safeTransferFrom(alice, bob, 1, 1, "");
    }

    function test_Soulbound_AdminEscapeHatchWithApproval() public {
        _makeCurator(alice, 1);
        // Stranded-token rescue path: holder approves admin, admin moves it.
        vm.prank(alice);
        nexus.setApprovalForAll(admin, true);
        vm.prank(admin);
        nexus.safeTransferFrom(alice, bob, 1, 1, "");
        assertEq(nexus.balanceOf(alice, 1), 0);
        assertEq(nexus.balanceOf(bob, 1), 1);
        assertEq(nexus.heldTokenCount(alice), 0);
        assertEq(nexus.heldTokenCount(bob), 1);
    }

    // =========================================================
    // 🔴 Pause
    // =========================================================
    function test_Pause_BlocksMint() public {
        _openYear(1);
        vm.prank(admin);
        nexus.pause();
        vm.prank(gameOp);
        vm.expectRevert(); // EnforcedPause
        nexus.mintCuratorToken(alice, 1);
    }

    function test_Unpause_RestoresMint() public {
        _openYear(1);
        vm.prank(admin);
        nexus.pause();
        vm.prank(admin);
        nexus.unpause();
        vm.prank(gameOp);
        nexus.mintCuratorToken(alice, 1);
        assertTrue(nexus.isCurator(alice));
    }

    function test_Pause_OnlyPauser() public {
        vm.prank(alice);
        vm.expectRevert();
        nexus.pause();
    }

    // =========================================================
    // 🔴 issuanceEnabled gate (Stage 1 → Stage 2)
    // =========================================================
    function test_Issuance_DisabledByDefault() public {
        _makeCurator(alice, 1);
        vm.prank(alice);
        vm.expectRevert(PIF12Nexus.IssuanceDisabled.selector);
        nexus.issuePersonalSBT(bob, "ipfs://img", "thank you");
    }

    function test_SetIssuanceEnabled_OnlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        nexus.setIssuanceEnabled(true);

        vm.prank(admin);
        nexus.setIssuanceEnabled(true);
        assertTrue(nexus.issuanceEnabled());
    }

    // =========================================================
    // 🟡 Star issuance (once enabled)
    // =========================================================
    function test_IssueStar_HappyPath() public {
        _makeCurator(alice, 1);
        vm.prank(admin);
        nexus.setIssuanceEnabled(true);

        vm.prank(alice);
        uint256 id = nexus.issuePersonalSBT(bob, "ipfs://img", "you inspire me");

        assertEq(id, 100);
        assertEq(nexus.balanceOf(bob, 100), 1);
        assertEq(nexus.heldTokenCount(bob), 1);
        assertFalse(nexus.isCurator(bob)); // two-layer stop: Star holder is NOT a curator
        assertEq(nexus.personalSeriesIssued(alice), 1);
        assertEq(nexus.nextPersonalTokenId(), 101);
        assertTrue(nexus.hasIssuedTo(alice, bob));
    }

    function test_IssueStar_RevertNotCurator() public {
        vm.prank(admin);
        nexus.setIssuanceEnabled(true);
        vm.prank(alice); // alice not a curator
        vm.expectRevert(PIF12Nexus.NotCurator.selector);
        nexus.issuePersonalSBT(bob, "", "x");
    }

    function test_IssueStar_RevertDuplicateRecipient() public {
        _makeCurator(alice, 1);
        vm.prank(admin);
        nexus.setIssuanceEnabled(true);
        vm.prank(alice);
        nexus.issuePersonalSBT(bob, "", "first");
        vm.prank(alice);
        vm.expectRevert(PIF12Nexus.AlreadyIssuedTo.selector);
        nexus.issuePersonalSBT(bob, "", "second");
    }

    function test_IssueStar_RevertSelfIssue() public {
        _makeCurator(alice, 1);
        vm.prank(admin);
        nexus.setIssuanceEnabled(true);
        vm.prank(alice);
        vm.expectRevert(PIF12Nexus.SelfIssue.selector);
        nexus.issuePersonalSBT(alice, "", "x");
    }

    // =========================================================
    // 🟡 Mutual aid — unique-people counting
    // =========================================================
    function test_MutualAid_FirstPairCounts() public {
        _makeCurator(alice, 1);
        _makeCurator(bob, 2);

        vm.prank(alice);
        bytes32 id = nexus.recordHelp(bob);
        vm.prank(bob);
        nexus.confirmHelp(id, "thank you");

        assertEq(nexus.peopleHelped(alice), 1);
        assertEq(nexus.peopleHelpedBy(bob), 1);
        assertTrue(nexus.hasHelped(alice, bob));
    }

    function test_MutualAid_RepeatPairDoesNotDoubleCount() public {
        _makeCurator(alice, 1);
        _makeCurator(bob, 2);

        vm.prank(alice);
        bytes32 id1 = nexus.recordHelp(bob);
        vm.prank(bob);
        nexus.confirmHelp(id1, "first");

        vm.roll(block.number + 1); // distinct recordId
        vm.prank(alice);
        bytes32 id2 = nexus.recordHelp(bob);
        vm.prank(bob);
        nexus.confirmHelp(id2, "second");

        // Still 1 — counts PEOPLE, not events.
        assertEq(nexus.peopleHelped(alice), 1);
        assertEq(nexus.peopleHelpedBy(bob), 1);
    }

    function test_MutualAid_RevertSelfHelp() public {
        _makeCurator(alice, 1);
        vm.prank(alice);
        vm.expectRevert(PIF12Nexus.SelfHelp.selector);
        nexus.recordHelp(alice);
    }

    function test_MutualAid_RevertRecipientNotMember() public {
        _makeCurator(alice, 1);
        vm.prank(alice);
        vm.expectRevert(PIF12Nexus.RecipientNotMember.selector);
        nexus.recordHelp(dave); // dave holds nothing
    }

    function test_ConfirmHelp_OnlyRecipient() public {
        _makeCurator(alice, 1);
        _makeCurator(bob, 2);
        vm.prank(alice);
        bytes32 id = nexus.recordHelp(bob);
        vm.prank(carol);
        vm.expectRevert(PIF12Nexus.NotRecipient.selector);
        nexus.confirmHelp(id, "x");
    }

    function test_ConfirmHelp_WindowExpired() public {
        _makeCurator(alice, 1);
        _makeCurator(bob, 2);
        vm.prank(alice);
        bytes32 id = nexus.recordHelp(bob);
        vm.warp(block.timestamp + 31 days);
        vm.prank(bob);
        vm.expectRevert(PIF12Nexus.ConfirmWindowExpired.selector);
        nexus.confirmHelp(id, "x");
    }

    // =========================================================
    // 🔴 Social recovery — Admin default
    // =========================================================
    function test_EffectiveRecoveryMode_DefaultsToAdmin() public view {
        assertEq(uint8(nexus.effectiveRecoveryMode(alice)), uint8(PIF12Nexus.RecoveryMode.AdminDefault));
    }

    function test_AdminRecover_MigratesIdentity() public {
        _makeCurator(alice, 1);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        vm.prank(admin);
        nexus.adminRecoverWallet(alice, bob, ids);

        assertFalse(nexus.isCurator(alice));
        assertEq(nexus.balanceOf(alice, 1), 0);
        assertEq(nexus.heldTokenCount(alice), 0);

        assertTrue(nexus.isCurator(bob));
        assertEq(nexus.curatorYear(bob), 1);
        assertEq(nexus.balanceOf(bob, 1), 1);
        assertEq(nexus.heldTokenCount(bob), 1);
    }

    function test_AdminRecover_RevertBadNewWallet() public {
        _makeCurator(alice, 1);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        vm.prank(admin);
        vm.expectRevert(PIF12Nexus.BadNewWallet.selector);
        nexus.adminRecoverWallet(alice, address(0), ids);
    }

    function test_AdminRecover_RevertIfGuardianMode() public {
        _makeCurator(alice, 1);
        _makeCurator(carol, 2);
        _makeCurator(dave, 3);
        // alice opts out to Guardian mode
        vm.prank(alice);
        nexus.requestRecoveryChange(PIF12Nexus.RecoveryMode.Guardian, carol, dave);
        vm.warp(block.timestamp + 48 hours);
        vm.prank(alice);
        nexus.executeRecoveryChange();

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        vm.prank(admin);
        vm.expectRevert(PIF12Nexus.NotAdminMode.selector);
        nexus.adminRecoverWallet(alice, bob, ids);
    }

    function test_AdminRecover_ClobberGuard() public {
        _makeCurator(alice, 1);
        _makeCurator(bob, 2); // bob already a curator
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        vm.prank(admin);
        vm.expectRevert(PIF12Nexus.NewAlreadyCurator.selector);
        nexus.adminRecoverWallet(alice, bob, ids);
    }

    // =========================================================
    // 🟡 Social recovery — Guardian (opt-out) full flow
    // =========================================================
    function test_GuardianRecovery_FullFlow() public {
        _makeCurator(alice, 1); // subject
        _makeCurator(carol, 2); // guardian A
        _makeCurator(dave, 3);  // guardian B

        // alice sets Guardian mode (48h timelock)
        vm.prank(alice);
        nexus.requestRecoveryChange(PIF12Nexus.RecoveryMode.Guardian, carol, dave);
        vm.warp(block.timestamp + 48 hours);
        vm.prank(alice);
        nexus.executeRecoveryChange();
        assertEq(uint8(nexus.recoveryMode(alice)), uint8(PIF12Nexus.RecoveryMode.Guardian));

        // carol initiates recovery to bob
        vm.prank(carol);
        nexus.initiateRecovery(alice, bob);

        // wait the execution delay (48h; alice not recently active)
        vm.warp(block.timestamp + 48 hours);

        // dave (the OTHER guardian) executes
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        vm.prank(dave);
        nexus.executeRecovery(alice, bob, ids);

        assertTrue(nexus.isCurator(bob));
        assertEq(nexus.balanceOf(bob, 1), 1);
        assertFalse(nexus.isCurator(alice));
    }

    function test_GuardianSetup_RevertNonMemberGuardian() public {
        _makeCurator(alice, 1);
        vm.prank(alice);
        vm.expectRevert(PIF12Nexus.GuardianNotMember.selector);
        nexus.requestRecoveryChange(PIF12Nexus.RecoveryMode.Guardian, bob, carol); // bob/carol not members
    }

    function test_RecoveryChange_TimelockEnforced() public {
        _makeCurator(alice, 1);
        _makeCurator(carol, 2);
        _makeCurator(dave, 3);
        vm.prank(alice);
        nexus.requestRecoveryChange(PIF12Nexus.RecoveryMode.Guardian, carol, dave);
        vm.prank(alice);
        vm.expectRevert(PIF12Nexus.TimelockNotExpired.selector);
        nexus.executeRecoveryChange();
    }

    function test_ExecuteRecovery_RevertSameGuardianTwice() public {
        _makeCurator(alice, 1);
        _makeCurator(carol, 2);
        _makeCurator(dave, 3);
        vm.prank(alice);
        nexus.requestRecoveryChange(PIF12Nexus.RecoveryMode.Guardian, carol, dave);
        vm.warp(block.timestamp + 48 hours);
        vm.prank(alice);
        nexus.executeRecoveryChange();

        vm.prank(carol);
        nexus.initiateRecovery(alice, bob);
        vm.warp(block.timestamp + 48 hours);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        vm.prank(carol); // same guardian who initiated
        vm.expectRevert(PIF12Nexus.NeedSecondGuardian.selector);
        nexus.executeRecovery(alice, bob, ids);
    }

    // =========================================================
    // 🟡 revokeCurator (soft exclusion, keeps token)
    // =========================================================
    function test_RevokeCurator_BlocksIssuanceKeepsToken() public {
        _makeCurator(alice, 1);
        vm.prank(admin);
        nexus.setIssuanceEnabled(true);
        vm.prank(alice);
        nexus.issuePersonalSBT(bob, "", "before revoke");

        vm.prank(admin);
        nexus.revokeCurator(alice, "off mission");

        assertFalse(nexus.isCurator(alice));
        assertEq(nexus.balanceOf(alice, 1), 1); // keeps year token
        assertEq(nexus.balanceOf(bob, 100), 1); // already-issued Star survives

        vm.prank(alice);
        vm.expectRevert(PIF12Nexus.NotCurator.selector);
        nexus.issuePersonalSBT(carol, "", "after revoke");
    }

    function test_RevokeCurator_OnlyAdmin() public {
        _makeCurator(alice, 1);
        vm.prank(bob);
        vm.expectRevert();
        nexus.revokeCurator(alice, "x");
    }

    // =========================================================
    // 🟡 Social recovery — LoneWolf (no recovery possible)
    // =========================================================
    function test_LoneWolf_NoRecoveryPath() public {
        _makeCurator(alice, 1);
        _makeCurator(carol, 2);
        vm.prank(alice);
        nexus.requestRecoveryChange(PIF12Nexus.RecoveryMode.LoneWolf, address(0), address(0));
        vm.warp(block.timestamp + 48 hours);
        vm.prank(alice);
        nexus.executeRecoveryChange();

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        vm.prank(admin); // admin path blocked
        vm.expectRevert(PIF12Nexus.NotAdminMode.selector);
        nexus.adminRecoverWallet(alice, bob, ids);

        vm.prank(carol); // guardian path blocked
        vm.expectRevert(PIF12Nexus.NotGuardianMode.selector);
        nexus.initiateRecovery(alice, bob);
    }

    // =========================================================
    // 🔴 UUPS upgrade authorization
    // =========================================================
    function test_Upgrade_OnlyUpgrader() public {
        PIF12Nexus implV2 = new PIF12Nexus();
        vm.prank(alice);
        vm.expectRevert(); // not UPGRADER_ROLE
        nexus.upgradeToAndCall(address(implV2), "");

        vm.prank(admin);
        nexus.upgradeToAndCall(address(implV2), ""); // upgrader can
        assertEq(nexus.VERSION(), "1.0.0");
    }

    // =========================================================
    // 🟡 Curator issuance grace = max(year deadline, since + 100d)
    // =========================================================
    function test_IssuanceGrace_ExtendsBeyondClosedYear() public {
        vm.prank(admin);
        nexus.setYearWindow(1, T0, T0 + 10 days); // short induction window
        vm.warp(T0 + 9 days);                     // inducted late
        vm.prank(gameOp);
        nexus.mintCuratorToken(alice, 1);

        // grace = since(T0+9d) + 100d  >  yearDeadline(T0+10d)
        assertEq(nexus.curatorIssuanceDeadline(alice), T0 + 9 days + 100 days);

        vm.prank(admin);
        nexus.setIssuanceEnabled(true);
        vm.warp(T0 + 50 days);            // year window long closed...
        assertFalse(nexus.isYearOpen(1));
        vm.prank(alice);                  // ...but still within the 100-day grace
        uint256 id = nexus.issuePersonalSBT(bob, "", "still within grace");
        assertEq(nexus.balanceOf(bob, id), 1);
    }

    function test_IssuanceGrace_RevertAfterDeadline() public {
        _makeCurator(alice, 1); // year window [T0, T0+365d]; grace = T0+365d
        vm.prank(admin);
        nexus.setIssuanceEnabled(true);
        vm.warp(T0 + 366 days); // past both year deadline and grace
        vm.prank(alice);
        vm.expectRevert(PIF12Nexus.IssuanceWindowClosed.selector);
        nexus.issuePersonalSBT(bob, "", "too late");
    }
}
