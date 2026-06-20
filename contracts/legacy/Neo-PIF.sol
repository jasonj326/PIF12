// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title  NeoPIF (Pay It Forward — 12-Year Legacy, V7)
 * @notice A 12-year Web3 social experiment combining five systems:
 *         (1) Soulbound Tokens (SBT)        — non-transferable on-chain identity.
 *         (2) PIF Ledger (福報) — Pay It Forward value tracking blessings received.
 *         (3) Co-Attested Help Records — dual-signature attestation flow.
 *         (4) Social Recovery — dual-guardian, time-locked wallet recovery.
 *         (5) Gasless Transactions (ERC-2771).
 *
 * @dev    V7 PHILOSOPHICAL REDESIGN (vs V6 karma ledger):
 *
 *         FROM ZERO-SUM KARMA TO PAY-IT-FORWARD FLOW
 *         V6 karma was zero-sum: A helps B → A's karma +N, B's karma -N.
 *         This implied "giving = sacrifice," conflicting with Pay-It-Forward's spirit.
 *         V7 reframes: A helps B → only B's PIF increases. Higher PIF = "more blessed,
 *         less lonely." Lower PIF = "yet-to-be-reached" — an invitation signal for
 *         outreach, not a moral deficit.
 *
 *         GIVING IS NOT REWARDED, BUT IS RECORDED
 *         The giver's PIF does not increase. Instead, totalHelpsGiven counter
 *         increments — visible on profile as "Helped N people" history (like a
 *         GitHub contribution graph). This rewards intrinsic motivation; the
 *         system records the fact without creating a leaderboard score.
 *
 *         CO-ATTESTATION (DUAL SIGNATURE) PREVENTS UNILATERAL GAMING
 *         Step 1: Giver calls recordHelpGiven(recipient, amount) — creates a
 *                 pending record. No PIF flows yet.
 *         Step 2: Recipient calls confirmHelpReceived(recordId) within
 *                 HELP_CONFIRMATION_WINDOW (30 days) — PIF flows to recipient.
 *         Giver cannot unilaterally boost recipient (no consent = no value).
 *         Recipient cannot fabricate (no giver attestation = no claim).
 *
 *         DUAL METRICS: PEOPLE COUNT (人數) AND EVENT COUNT (人次)
 *         Each address tracks four counters on top of pifValue:
 *           uniqueRecipientsHelped     — distinct people you've helped
 *           totalHelpsGiven            — total help events you've given
 *           uniqueGiversReceivedFrom   — distinct people who've helped you
 *           totalHelpsReceived         — total help events you've received
 *         Two counters together reveal the give/receive pattern (wide-shallow
 *         vs narrow-deep) without creating a single leaderboard score.
 *
 *         FUTURE-PROOF HOOK: SAME-PAIR COOLDOWN (PRE-DEPLOYED, DISABLED BY DEFAULT)
 *         sameHelperCooldown gates how often the same (giver, recipient) pair
 *         can record confirmed help. Initial value 0 means "no throttle" — Y1
 *         routine flow is unaffected. If pair-level inflation is detected later
 *         (A repeatedly boosting B), admin calls setSameHelperCooldown(seconds)
 *         to enable enforcement without a contract upgrade. Capped at MAX_COOLDOWN
 *         (30 days) to prevent governance attack via excessive cooldown.
 *
 *         RECOVERY = FULL BLESSING TRANSFER (NOT REDISTRIBUTION)
 *         V6 split positive karma across newWallet + 2 guardians (shared-fate
 *         redistribution). V7 transfers PIF and counters fully to newWallet —
 *         your blessings follow you. Guardians witness but do not share, because
 *         recovery is an emergency mechanism, not a reward distribution.
 *
 *         NO NEGATIVE VALUES, NO REINCARNATION TAX
 *         PIF is uint256 and bounded [0, PIF_MAX]. The V6 Reincarnation Tax
 *         (1.33x amplified penalty on negative karma) is removed entirely.
 *         Misconduct is handled by GAME_ROLE admin penalty (capped at current
 *         balance, never goes below zero).
 *
 *         BLESSING FREEZE (RENAMED FROM PRIVILEGE FREEZE)
 *         For 30 days after recovery, the wallet cannot receive new help
 *         confirmations (prevents post-recovery boost farming). Same mechanism
 *         as V6's isPrivilegeFrozen, renamed for semantic clarity.
 *
 *         GASLESS via TRUSTED FORWARDER — unchanged from V6.
 *
 *         AUDIT NOTE: V7 is a fresh deployment, not a UUPS upgrade of V6 —
 *         storage layout is incompatible (karmaPoints removed, pifValue added,
 *         counters added). Requires fresh security audit before mainnet.
 */
contract NeoPIF is
    ERC1155Upgradeable,
    AccessControlUpgradeable,
    ERC1155PausableUpgradeable,
    ERC1155SupplyUpgradeable,
    UUPSUpgradeable
{
    // ==========================================
    // Roles
    // ==========================================
    bytes32 public constant MINTER_ROLE   = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");
    /// @dev Reserved for emergency penalty operations (anti-cheating). NOT used
    ///      for routine value changes — those flow through co-attestation only.
    bytes32 public constant GAME_ROLE     = keccak256("GAME_ROLE");

    // ==========================================
    // Time Constants
    // ==========================================
    uint256 public constant MIN_RECOVERY_DELAY = 48 hours;
    uint256 public constant MAX_RECOVERY_DELAY = 30 days;
    uint256 public constant DEFAULT_RECOVERY_DELAY = 48 hours;
    uint256 public constant ACTIVE_WINDOW = 14 days;
    uint256 public constant ACTIVE_ACCOUNT_EXTENDED_DELAY = 7 days;

    /// @dev Recipient must confirm a help record within this window or it expires.
    ///      Anyone can prune expired records (gas reclaimed via SSTORE refund).
    uint256 public constant HELP_CONFIRMATION_WINDOW = 30 days;

    // ==========================================
    // PIF Bounds & Help Limits
    // ==========================================

    /// @dev Maximum PIF value per address. Cap is conservative; helps can exceed
    ///      this in attestation, but the recipient's balance saturates at cap.
    uint256 public constant PIF_MAX = 100_000;

    /// @dev Maximum amount per single help attestation. Prevents whale-style
    ///      single-tx PIF inflation; encourages many small acts over one big one.
    uint256 public constant MAX_AMOUNT_PER_ATTEST = 1_000;

    /// @dev Upper bound on sameHelperCooldown to prevent governance attack: a malicious
    ///      admin cannot freeze the help flow indefinitely by setting cooldown to infinity.
    uint256 public constant MAX_COOLDOWN = 30 days;

    // ==========================================
    // State Variables
    // ==========================================

    /// @dev PIF (Pay-It-Forward Value). Tracks blessings received over time.
    ///      Monotonically non-decreasing in normal play; only reduced by GAME_ROLE
    ///      admin penalty (anti-cheating) or recovery (full transfer to new wallet).
    mapping(address => uint256) public pifValue;

    /// @dev Lifetime counter of confirmed help events given (人次 — instances).
    ///      Incremented once per confirmed help, regardless of recipient identity.
    mapping(address => uint256) public totalHelpsGiven;

    /// @dev Lifetime counter of confirmed help events received (人次 — instances).
    ///      Symmetric with totalHelpsGiven on the recipient side. Network totals
    ///      equal across all addresses (excluding pending records).
    mapping(address => uint256) public totalHelpsReceived;

    /// @dev Lifetime counter of distinct people a giver has helped (人數 — unique reach).
    ///      Incremented only on the first confirmed help to a new recipient address.
    ///      A giver who helped the same person 100 times has uniqueRecipientsHelped == 1,
    ///      while totalHelpsGiven == 100. The two metrics together reveal pattern:
    ///      "wide and shallow" vs "narrow and deep" giving.
    mapping(address => uint256) public uniqueRecipientsHelped;

    /// @dev Lifetime counter of distinct people who have helped a recipient (人數).
    ///      Symmetric with uniqueRecipientsHelped on the recipient side.
    mapping(address => uint256) public uniqueGiversReceivedFrom;

    /// @dev Per-pair tracking: has this (giver, recipient) pair ever recorded a
    ///      confirmed help before? Used to decide whether confirmHelpReceived should
    ///      increment uniqueRecipientsHelped[giver]. First-time pairs increment; repeats do not.
    mapping(address => mapping(address => bool)) public hasHelpedRecipient;

    /// @dev Symmetric per-pair tracking on the recipient side.
    mapping(address => mapping(address => bool)) public hasReceivedFromGiver;

    /// @dev Timestamp of the last confirmed help between a specific (giver, recipient) pair.
    ///      Used by Hook 1 (same-pair cooldown) to throttle pair-level inflation when
    ///      sameHelperCooldown > 0. Default value 0 means "no prior help" (cooldown passes).
    mapping(address => mapping(address => uint256)) public lastHelpAt;

    /// @dev Hook 1: Minimum seconds required between two confirmed helps from the same
    ///      (giver, recipient) pair. Initial value 0 disables the check (full backward
    ///      compatibility with simple flow). Admin can raise via setSameHelperCooldown.
    ///      Capped at MAX_COOLDOWN (30 days) to prevent governance-attack via excessive
    ///      cooldown that effectively blocks the help flow.
    ///
    ///      Why predeploy this disabled rather than wait and upgrade later:
    ///      contract upgrades are expensive (re-audit, governance, user comms). A simple
    ///      uint256 + a single require() check, deployed disabled, lets us flip the switch
    ///      via a single admin transaction the day inflation is detected. Cost today: ~1
    ///      storage slot + ~30 gas per confirm. Cost of not having it later: full upgrade cycle.
    uint256 public sameHelperCooldown;

    struct PendingHelpRecord {
        address giver;
        address recipient;
        uint256 amount;
        uint256 attestedAt;
        bool exists;
    }
    /// @dev Pending help records by deterministic ID. Created by giver in step 1,
    ///      finalized by recipient confirmation in step 2 (or cancelled / expired).
    mapping(bytes32 => PendingHelpRecord) public pendingHelpRecords;

    /// @dev Per-recipient list of pending record IDs. Front-end uses this to surface
    ///      "you have N attestations awaiting your confirmation." Items remain in
    ///      the array after deletion of the record itself; client filters by `exists`.
    mapping(address => bytes32[]) public pendingByRecipient;

    struct GuardianSet {
        address guardianA;
        address guardianB;
    }
    /// @dev Active guardian pairs per wallet.
    mapping(address => GuardianSet) public customGuardians;

    struct PendingGuardianChange {
        GuardianSet newGuardians;
        uint256 effectiveTime;
    }
    /// @dev Staged guardian changes awaiting their 48-hour time-lock.
    mapping(address => PendingGuardianChange) public pendingGuardianChanges;

    struct RecoveryRequest {
        address targetWallet;
        address firstApprover;
        uint256 initiatedAt;
    }
    /// @dev oldWallet => tokenId => pending recovery request.
    mapping(address => mapping(uint256 => RecoveryRequest)) public pendingRecoveries;

    /// @dev Tracks last recovery timestamp for 6-month cooldown + 30-day blessing freeze.
    mapping(address => uint256) public lastRecoveryTime;

    /// @dev User-defined execution delay for recovery (48h–30d). Falls back to default if zero.
    mapping(address => uint256) public recoveryDelay;

    /// @dev Auto-updated on help confirmation (recipient side) and by manual heartbeat().
    ///      Used to detect active accounts → adds ACTIVE_ACCOUNT_EXTENDED_DELAY on top
    ///      of base recovery delay for active wallets.
    mapping(address => uint256) public lastActiveTime;

    // --- Lone Wolf Mode ---
    mapping(address => bool) public adminRecoveryOptOut;

    struct PendingOptOutRequest {
        bool requestedStatus;
        uint256 effectiveTime;
    }
    mapping(address => PendingOptOutRequest) public pendingOptOuts;

    // --- Gasless Meta-Transactions (ERC-2771) ---
    address public trustedForwarder;

    // ==========================================
    // Events
    // ==========================================

    // Help attestation lifecycle
    event HelpRecorded(bytes32 indexed recordId, address indexed giver, address indexed recipient, uint256 amount);
    event HelpConfirmed(bytes32 indexed recordId, address indexed recipient, uint256 amountAdded, uint256 newPifValue);
    event HelpCancelled(bytes32 indexed recordId, address indexed giver);
    event HelpExpired(bytes32 indexed recordId);

    // PIF state changes (admin)
    event AdminPenalty(address indexed user, uint256 amountReduced, string reason);
    event CooldownUpdated(uint256 newCooldownSeconds);

    // Recovery + blessing transfer
    event BlessingTransferred(
        address indexed oldWallet,
        address indexed newWallet,
        uint256 pifTransferred,
        uint256 uniqueHelpedTransferred,
        uint256 totalHelpsGivenTransferred,
        uint256 uniqueReceivedTransferred,
        uint256 totalHelpsReceivedTransferred
    );

    // Existing events from V6 (renamed where appropriate)
    event GuardianChangeRequested(address indexed user, address guardianA, address guardianB, uint256 effectiveTime);
    event GuardianChangeCancelled(address indexed user);
    event GuardiansSet(address indexed user, address guardianA, address guardianB);

    event RecoveryInitiated(address indexed oldWallet, address indexed newWallet, uint256 tokenId, address initiator);
    event RecoveryExecuted(address indexed oldWallet, address indexed newWallet, uint256 tokenId);
    event RecoveryCancelled(address indexed oldWallet, uint256 tokenId);
    event RecoveryDelayUpdated(address indexed user, uint256 newDelay);

    event Heartbeat(address indexed user, uint256 timestamp);

    event AdminRecoveryOptOutRequested(address indexed user, bool requestedStatus, uint256 effectiveTime);
    event AdminRecoveryOptOutCancelled(address indexed user);
    event AdminRecoveryOptOutExecuted(address indexed user, bool newStatus);

    event TrustedForwarderUpdated(address indexed oldForwarder, address indexed newForwarder);

    // ==========================================
    // Constructor / Initialiser
    // ==========================================
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin,
        address minter,
        address _forwarder
    ) initializer public {
        __ERC1155_init("ipfs://PENDING_URI/{id}.json");
        __AccessControl_init();
        __ERC1155Pausable_init();
        __ERC1155Supply_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE,        minter);
        _grantRole(UPGRADER_ROLE,      defaultAdmin);
        _grantRole(PAUSER_ROLE,        defaultAdmin);

        trustedForwarder = _forwarder;
    }

    // ==========================================
    // ERC-2771 Gasless Meta-Transaction Support
    // ==========================================
    function setTrustedForwarder(address _forwarder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit TrustedForwarderUpdated(trustedForwarder, _forwarder);
        trustedForwarder = _forwarder;
    }

    function isTrustedForwarder(address forwarder) public view returns (bool) {
        return forwarder == trustedForwarder;
    }

    function _msgSender()
        internal view virtual
        override(ContextUpgradeable)
        returns (address sender)
    {
        if (isTrustedForwarder(msg.sender) && msg.data.length >= 20) {
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
            return sender;
        }
        return super._msgSender();
    }

    function _msgData()
        internal view virtual
        override(ContextUpgradeable)
        returns (bytes calldata)
    {
        if (isTrustedForwarder(msg.sender) && msg.data.length >= 20) {
            return msg.data[:msg.data.length - 20];
        } else {
            return super._msgData();
        }
    }

    // ==========================================
    // Emergency Pause (Kill Switch)
    // ==========================================
    function pause()   public onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() public onlyRole(PAUSER_ROLE) { _unpause(); }

    // ==========================================
    // Minting & Metadata
    // ==========================================
    function mintSBT(address to, uint256 id, uint256 amount)
        public onlyRole(MINTER_ROLE)
    {
        _mint(to, id, amount, "");
    }

    function mintBatchSBT(address to, uint256[] memory ids, uint256[] memory amounts)
        public onlyRole(MINTER_ROLE)
    {
        _mintBatch(to, ids, amounts, "");
    }

    function setURI(string memory newuri) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    // ==========================================
    // Heartbeat & Custom Recovery Delay (unchanged)
    // ==========================================
    function setRecoveryDelay(uint256 delayInSeconds) external whenNotPaused {
        require(
            delayInSeconds >= MIN_RECOVERY_DELAY && delayInSeconds <= MAX_RECOVERY_DELAY,
            "Recovery: Delay must be between 48 hours and 30 days"
        );
        recoveryDelay[_msgSender()] = delayInSeconds;
        emit RecoveryDelayUpdated(_msgSender(), delayInSeconds);
    }

    function getRecoveryDelay(address user) public view returns (uint256) {
        uint256 custom = recoveryDelay[user];
        return custom > 0 ? custom : DEFAULT_RECOVERY_DELAY;
    }

    function heartbeat() external whenNotPaused {
        lastActiveTime[_msgSender()] = block.timestamp;
        emit Heartbeat(_msgSender(), block.timestamp);
    }

    function isRecentlyActive(address user) public view returns (bool) {
        return block.timestamp < lastActiveTime[user] + ACTIVE_WINDOW;
    }

    // ==========================================
    // Blessing Freeze (renamed from Privilege Freeze)
    // ==========================================

    /// @notice Returns true if the wallet is within the 30-day blessing freeze after recovery.
    ///         Frozen wallets cannot have helps confirmed to them (prevents post-recovery
    ///         boost farming). Mirrors V6's isPrivilegeFrozen semantics, renamed for clarity.
    function isBlessingFrozen(address user) public view returns (bool) {
        return block.timestamp < lastRecoveryTime[user] + 30 days;
    }

    // ==========================================
    // PIF Co-Attestation Flow (NEW — replaces V6 addKarma)
    // ==========================================

    /**
     * @notice Step 1: Giver records that they helped a recipient.
     * @dev    Creates a pending record. No PIF flows until recipient confirms.
     *         Self-help is forbidden. Both parties must hold an SBT (token id 0).
     *         Recipient must not be in blessing freeze.
     * @return recordId Deterministic id derived from giver + recipient + amount + time.
     */
    function recordHelpGiven(address recipient, uint256 amount)
        external
        whenNotPaused
        returns (bytes32 recordId)
    {
        require(recipient != address(0),                   "PIF: Invalid recipient");
        require(recipient != _msgSender(),                 "PIF: Cannot record help to yourself");
        require(amount > 0 && amount <= MAX_AMOUNT_PER_ATTEST, "PIF: Amount out of range");
        require(balanceOf(_msgSender(), 0) > 0,            "PIF: Giver must hold an SBT");
        require(balanceOf(recipient, 0) > 0,               "PIF: Recipient must hold an SBT");
        require(!isBlessingFrozen(recipient),              "PIF: Recipient is in 30-day blessing freeze");

        recordId = keccak256(
            abi.encodePacked(_msgSender(), recipient, amount, block.timestamp, block.number)
        );
        require(!pendingHelpRecords[recordId].exists, "PIF: Record collision (retry next block)");

        pendingHelpRecords[recordId] = PendingHelpRecord({
            giver:       _msgSender(),
            recipient:   recipient,
            amount:      amount,
            attestedAt:  block.timestamp,
            exists:      true
        });
        pendingByRecipient[recipient].push(recordId);

        emit HelpRecorded(recordId, _msgSender(), recipient, amount);
    }

    /**
     * @notice Step 2: Recipient confirms the help — PIF flows.
     * @dev    Only the recipient named in the record can confirm. Must be within
     *         HELP_CONFIRMATION_WINDOW (30 days) of attestation. PIF saturates at
     *         PIF_MAX without reverting (no DoS on near-cap wallets).
     */
    function confirmHelpReceived(bytes32 recordId) external whenNotPaused {
        PendingHelpRecord storage rec = pendingHelpRecords[recordId];
        require(rec.exists,                                              "PIF: Record does not exist");
        require(rec.recipient == _msgSender(),                           "PIF: Only recipient can confirm");
        require(block.timestamp <= rec.attestedAt + HELP_CONFIRMATION_WINDOW, "PIF: Confirmation window expired");

        // Hook 1: same-pair cooldown check. No-op when sameHelperCooldown == 0 (initial state).
        // Prevents A from rapidly repeating help-confirmations on the same B address.
        require(
            sameHelperCooldown == 0 ||
            block.timestamp >= lastHelpAt[rec.giver][rec.recipient] + sameHelperCooldown,
            "PIF: Same-pair cooldown active"
        );

        // Saturating add — never reverts, just caps at PIF_MAX.
        uint256 current = pifValue[rec.recipient];
        uint256 target  = current + rec.amount;
        uint256 newPif  = target > PIF_MAX ? PIF_MAX : target;
        uint256 added   = newPif - current;

        pifValue[rec.recipient] = newPif;

        // Event counters (人次 — instances).
        totalHelpsGiven[rec.giver]        += 1;
        totalHelpsReceived[rec.recipient] += 1;

        // Unique counters (人數 — distinct addresses). First-time pair only.
        if (!hasHelpedRecipient[rec.giver][rec.recipient]) {
            hasHelpedRecipient[rec.giver][rec.recipient] = true;
            uniqueRecipientsHelped[rec.giver] += 1;
        }
        if (!hasReceivedFromGiver[rec.recipient][rec.giver]) {
            hasReceivedFromGiver[rec.recipient][rec.giver] = true;
            uniqueGiversReceivedFrom[rec.recipient] += 1;
        }

        // Record pair timestamp for Hook 1 cooldown enforcement (whether active or not).
        lastHelpAt[rec.giver][rec.recipient] = block.timestamp;

        // Auto-heartbeat — receiving help counts as engagement.
        lastActiveTime[rec.recipient] = block.timestamp;

        emit HelpConfirmed(recordId, rec.recipient, added, newPif);

        delete pendingHelpRecords[recordId];
        // Note: pendingByRecipient is not pruned here for gas efficiency.
        // Front-end filters by `pendingHelpRecords[id].exists`.
    }

    /**
     * @notice Giver retracts a pending help record before recipient confirms.
     * @dev    Useful if amount or recipient was wrong. Only original giver can cancel.
     */
    function cancelHelpRecord(bytes32 recordId) external whenNotPaused {
        PendingHelpRecord storage rec = pendingHelpRecords[recordId];
        require(rec.exists,                "PIF: Record does not exist");
        require(rec.giver == _msgSender(), "PIF: Only giver can cancel");

        emit HelpCancelled(recordId, rec.giver);
        delete pendingHelpRecords[recordId];
    }

    /**
     * @notice Anyone can prune an expired record. No PIF flows; just cleanup.
     * @dev    Incentive: SSTORE refund offsets gas cost. Public benefit: keeps
     *         pendingByRecipient list from growing unboundedly.
     */
    function pruneExpiredRecord(bytes32 recordId) external {
        PendingHelpRecord storage rec = pendingHelpRecords[recordId];
        require(rec.exists,                                              "PIF: Record does not exist");
        require(block.timestamp > rec.attestedAt + HELP_CONFIRMATION_WINDOW, "PIF: Not yet expired");

        emit HelpExpired(recordId);
        delete pendingHelpRecords[recordId];
    }

    /**
     * @notice Admin emergency penalty for cheating / abuse.
     * @dev    Reduces PIF; capped at current balance (never goes below zero).
     *         Reserved for GAME_ROLE — typically a community DAO multisig at Y3+.
     */
    function adminPenalty(address user, uint256 amount, string calldata reason)
        external
        onlyRole(GAME_ROLE)
        whenNotPaused
    {
        require(user != address(0), "PIF: Invalid user");
        uint256 current = pifValue[user];
        uint256 reduced = amount > current ? current : amount;
        pifValue[user]  = current - reduced;

        emit AdminPenalty(user, reduced, reason);
    }

    /**
     * @notice Hook 1 control: set the minimum seconds required between confirmed
     *         helps from the same (giver, recipient) pair.
     * @dev    Set to 0 to disable (default). Capped at MAX_COOLDOWN (30 days) to
     *         prevent governance attack via excessive cooldown blocking the help flow.
     *         Intended for activation only after detected pair-level inflation patterns;
     *         the routine flow should not require throttling in Y1.
     */
    function setSameHelperCooldown(uint256 cooldownSeconds)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(cooldownSeconds <= MAX_COOLDOWN, "PIF: Cooldown exceeds maximum");
        sameHelperCooldown = cooldownSeconds;
        emit CooldownUpdated(cooldownSeconds);
    }

    // ==========================================
    // View Helpers
    // ==========================================

    /// @notice Returns the list of pending record IDs for a given recipient.
    /// @dev    Front-end should filter by `pendingHelpRecords[id].exists` to
    ///         hide deleted/confirmed/cancelled records (list is append-only).
    function getPendingRecordsForRecipient(address recipient)
        external
        view
        returns (bytes32[] memory)
    {
        return pendingByRecipient[recipient];
    }

    /// @notice Convenience: returns a user's full profile summary in one call.
    /// @dev    Six fields cover both 人數 (unique addresses) and 人次 (event instances)
    ///         on both give and receive sides, plus the recovery-related freeze flag.
    function getProfile(address user)
        external
        view
        returns (
            uint256 pif,                          // 福報值
            uint256 uniquePeopleHelped,           // 幫助過的人數 (unique recipients)
            uint256 totalHelpInstances,           // 幫助過的人次 (total give events)
            uint256 uniqueHelpersReceivedFrom,    // 被幾個人幫過 (unique givers)
            uint256 totalReceivedInstances,       // 被幫過的人次 (total receive events)
            bool    blessingFrozen                // 30-day post-recovery freeze flag
        )
    {
        pif                       = pifValue[user];
        uniquePeopleHelped        = uniqueRecipientsHelped[user];
        totalHelpInstances        = totalHelpsGiven[user];
        uniqueHelpersReceivedFrom = uniqueGiversReceivedFrom[user];
        totalReceivedInstances    = totalHelpsReceived[user];
        blessingFrozen            = isBlessingFrozen(user);
    }

    // ==========================================
    // Lone Wolf Mode (Opt-out of Admin Recovery) — unchanged from V6
    // ==========================================
    function requestAdminRecoveryOptOut(bool optOut) external whenNotPaused {
        uint256 effectiveTime = block.timestamp + MIN_RECOVERY_DELAY;
        pendingOptOuts[_msgSender()] = PendingOptOutRequest(optOut, effectiveTime);
        emit AdminRecoveryOptOutRequested(_msgSender(), optOut, effectiveTime);
    }

    function cancelAdminRecoveryOptOut() external whenNotPaused {
        require(pendingOptOuts[_msgSender()].effectiveTime != 0, "Recovery: No pending opt-out request");
        delete pendingOptOuts[_msgSender()];
        emit AdminRecoveryOptOutCancelled(_msgSender());
    }

    function executeAdminRecoveryOptOut() external whenNotPaused {
        PendingOptOutRequest memory req = pendingOptOuts[_msgSender()];
        require(req.effectiveTime != 0,                  "Recovery: No pending opt-out request");
        require(block.timestamp >= req.effectiveTime,    "Recovery: Time-lock not expired yet");

        adminRecoveryOptOut[_msgSender()] = req.requestedStatus;
        delete pendingOptOuts[_msgSender()];
        emit AdminRecoveryOptOutExecuted(_msgSender(), req.requestedStatus);
    }

    // ==========================================
    // Guardian Management — unchanged from V6
    // ==========================================
    function requestGuardianChange(address guardianA, address guardianB) external whenNotPaused {
        require(guardianA != _msgSender() && guardianB != _msgSender(), "Recovery: Cannot be your own guardian");
        require(guardianA != guardianB,                                  "Recovery: Guardians must be different");
        require(guardianA != address(0) && guardianB != address(0),      "Recovery: Invalid guardian address");

        uint256 effectiveTime = block.timestamp + MIN_RECOVERY_DELAY;
        pendingGuardianChanges[_msgSender()] = PendingGuardianChange(
            GuardianSet(guardianA, guardianB),
            effectiveTime
        );
        emit GuardianChangeRequested(_msgSender(), guardianA, guardianB, effectiveTime);
    }

    function cancelGuardianChange() external whenNotPaused {
        require(pendingGuardianChanges[_msgSender()].effectiveTime != 0, "Recovery: No pending change");
        delete pendingGuardianChanges[_msgSender()];
        emit GuardianChangeCancelled(_msgSender());
    }

    function executeGuardianChange() external whenNotPaused {
        PendingGuardianChange memory pending = pendingGuardianChanges[_msgSender()];
        require(pending.effectiveTime != 0,               "Recovery: No pending guardian change");
        require(block.timestamp >= pending.effectiveTime, "Recovery: Time-lock not expired yet");

        customGuardians[_msgSender()] = pending.newGuardians;
        delete pendingGuardianChanges[_msgSender()];
        emit GuardiansSet(_msgSender(), pending.newGuardians.guardianA, pending.newGuardians.guardianB);
    }

    // ==========================================
    // Social Recovery — flow unchanged from V6, redistribution changed
    // ==========================================

    /**
     * @notice Admin-forced recovery for wallets with no custom guardians.
     * @dev    Blocked if owner opted out (Lone Wolf) or has set custom guardians.
     *         Karma penalty removed (V6); admin recovery now performs full PIF
     *         transfer like guardian recovery — but without guardian witnesses.
     */
    function adminRecoverWallet(address oldWallet, address newWallet, uint256 tokenId)
        external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused
    {
        require(!adminRecoveryOptOut[oldWallet],                       "Recovery: User opted out of Admin recovery (Lone Wolf)");
        require(customGuardians[oldWallet].guardianA == address(0),    "Recovery: User has custom guardians, Admin locked out");
        _processRecovery(oldWallet, newWallet, tokenId);
        emit RecoveryExecuted(oldWallet, newWallet, tokenId);
    }

    function initiateRecovery(address oldWallet, address newWallet, uint256 tokenId)
        external whenNotPaused
    {
        require(balanceOf(oldWallet, tokenId) > 0, "Recovery: Old wallet has no such token");
        require(
            pendingRecoveries[oldWallet][tokenId].firstApprover == address(0),
            "Recovery: A recovery is already pending"
        );

        GuardianSet memory guards = customGuardians[oldWallet];
        require(
            _msgSender() == guards.guardianA || _msgSender() == guards.guardianB,
            "Recovery: Not a designated guardian"
        );
        require(balanceOf(_msgSender(), tokenId) > 0, "Recovery: Guardian must hold an SBT");

        pendingRecoveries[oldWallet][tokenId] = RecoveryRequest(newWallet, _msgSender(), block.timestamp);
        emit RecoveryInitiated(oldWallet, newWallet, tokenId, _msgSender());
    }

    function cancelRecovery(address oldWallet, uint256 tokenId) external whenNotPaused {
        GuardianSet memory guards = customGuardians[oldWallet];
        require(
            _msgSender() == guards.guardianA || _msgSender() == guards.guardianB,
            "Recovery: Only guardians can cancel"
        );
        require(
            pendingRecoveries[oldWallet][tokenId].firstApprover != address(0),
            "Recovery: No pending recovery"
        );
        delete pendingRecoveries[oldWallet][tokenId];
        emit RecoveryCancelled(oldWallet, tokenId);
    }

    function executeRecovery(address oldWallet, address newWallet, uint256 tokenId)
        external whenNotPaused
    {
        GuardianSet memory guards = customGuardians[oldWallet];
        require(
            _msgSender() == guards.guardianA || _msgSender() == guards.guardianB,
            "Recovery: Not a designated guardian"
        );
        require(balanceOf(_msgSender(), tokenId) > 0, "Recovery: Guardian must hold an SBT");

        RecoveryRequest memory req = pendingRecoveries[oldWallet][tokenId];
        require(req.firstApprover != address(0),  "Recovery: No recovery initiated yet");
        require(req.targetWallet == newWallet,     "Recovery: Target wallet mismatch");
        require(req.firstApprover != _msgSender(), "Recovery: You cannot approve twice");

        uint256 requiredDelay = getRecoveryDelay(oldWallet);
        if (isRecentlyActive(oldWallet)) {
            requiredDelay += ACTIVE_ACCOUNT_EXTENDED_DELAY;
        }
        require(
            block.timestamp >= req.initiatedAt + requiredDelay,
            "Recovery: Execution time-lock has not expired yet"
        );

        delete pendingRecoveries[oldWallet][tokenId];
        _processRecovery(oldWallet, newWallet, tokenId);
        emit RecoveryExecuted(oldWallet, newWallet, tokenId);
    }

    // ==========================================
    // Core Recovery Logic — V7 Full Transfer
    // ==========================================

    /**
     * @dev V7 SEMANTIC CHANGE FROM V6:
     *      V6 redistributed positive karma across newWallet + 2 guardians,
     *      and amplified negative karma 1.33x (Reincarnation Tax).
     *      V7 simply transfers PIF + counters fully to newWallet — your
     *      blessings follow you. Guardians witness but do not share.
     *
     *      Rationale: PIF tracks blessings received (a personal history),
     *      not a shared moral pool. Splitting it across guardians during
     *      recovery would imply guardians "own" part of your blessing —
     *      which contradicts the Pay-It-Forward philosophy.
     *
     *      The 6-month cooldown + 30-day blessing freeze on both wallets
     *      remain the primary anti-abuse mechanisms (V6 inherited).
     */
    function _processRecovery(
        address oldWallet,
        address newWallet,
        uint256 tokenId
    ) internal {
        require(balanceOf(newWallet, tokenId) == 0,                                  "Recovery: Target wallet already holds this SBT");
        require(block.timestamp >= lastRecoveryTime[oldWallet] + 180 days,           "Recovery: Old wallet cannot be recovered again within 6 months");
        require(block.timestamp >= lastRecoveryTime[newWallet] + 180 days,           "Recovery: New wallet cannot accept recovery within 6 months");

        uint256 balance = balanceOf(oldWallet, tokenId);
        require(balance > 0, "Recovery: No tokens to recover");

        // SBT migration via Burn & Mint (bypasses Soulbound transfer lock).
        _burn(oldWallet, tokenId, balance);
        _mint(newWallet, tokenId, balance, "");

        // Full transfer of PIF state (blessings follow the person).
        uint256 pifAmt          = pifValue[oldWallet];
        uint256 givenAmt        = totalHelpsGiven[oldWallet];
        uint256 recvAmt         = totalHelpsReceived[oldWallet];
        uint256 uniqueGivenAmt  = uniqueRecipientsHelped[oldWallet];
        uint256 uniqueRecvAmt   = uniqueGiversReceivedFrom[oldWallet];

        // Saturating add on destination side (in case newWallet had any priors).
        uint256 newPifTarget = pifValue[newWallet] + pifAmt;
        pifValue[newWallet]              = newPifTarget > PIF_MAX ? PIF_MAX : newPifTarget;
        totalHelpsGiven[newWallet]       += givenAmt;
        totalHelpsReceived[newWallet]    += recvAmt;
        uniqueRecipientsHelped[newWallet]  += uniqueGivenAmt;
        uniqueGiversReceivedFrom[newWallet] += uniqueRecvAmt;

        // Wipe old wallet's state.
        pifValue[oldWallet]                = 0;
        totalHelpsGiven[oldWallet]         = 0;
        totalHelpsReceived[oldWallet]      = 0;
        uniqueRecipientsHelped[oldWallet]    = 0;
        uniqueGiversReceivedFrom[oldWallet]  = 0;

        // NOTE: pair-keyed mappings (hasHelpedRecipient, hasReceivedFromGiver, lastHelpAt)
        // are NOT migrated. Mappings cannot be iterated, so per-pair history of the old
        // wallet cannot be copied. Post-recovery, the new wallet starts with empty pair
        // history: any prior helper of the old wallet will count as a new unique pair
        // when helping the new wallet. Acceptable because the 6-month recovery cooldown
        // and 30-day blessing freeze prevent immediate exploitation of the reset state.

        // Start 6-month cooldown + 30-day blessing freeze on both wallets.
        lastRecoveryTime[newWallet] = block.timestamp;
        lastRecoveryTime[oldWallet] = block.timestamp;

        emit BlessingTransferred(
            oldWallet,
            newWallet,
            pifAmt,
            uniqueGivenAmt,
            givenAmt,
            uniqueRecvAmt,
            recvAmt
        );
    }

    // ==========================================
    // Soulbound Lock Mechanism — unchanged from V6
    // ==========================================
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155Upgradeable, ERC1155PausableUpgradeable, ERC1155SupplyUpgradeable) {
        if (from != address(0) && to != address(0)) {
            require(
                hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
                "NeoPIF: Transfers are locked. Tokens are Soulbound."
            );
        }
        super._update(from, to, ids, values);
    }

    // ==========================================
    // Upgrade Authorization
    // ==========================================
    function _authorizeUpgrade(address newImplementation)
        internal override onlyRole(UPGRADER_ROLE) {}

    // ==========================================
    // Interface Support
    // ==========================================
    function supportsInterface(bytes4 interfaceId)
        public view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ==========================================
    // Storage Gap for Future Upgrades
    // ==========================================
    // V7 uses ~21 state-variable slots (10 V6-inherited + 11 V7-new). Gap reduced
    // from V6's 50 → 29 to keep total reserved slots at 50, matching V6's footprint
    // for upgrade hygiene. New V7 vars: pifValue, totalHelpsGiven, totalHelpsReceived,
    // uniqueRecipientsHelped, uniqueGiversReceivedFrom, hasHelpedRecipient,
    // hasReceivedFromGiver, lastHelpAt, sameHelperCooldown, pendingHelpRecords,
    // pendingByRecipient (11 slots).
    uint256[29] private __gap;
}
