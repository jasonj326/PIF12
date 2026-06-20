// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title  PIF12 (Pay It Forward — 12-Year Legacy)
 * @notice A 12-year Web3 social experiment combining four systems:
 *         (1) Soulbound Tokens (SBT) — non-transferable on-chain identity.
 *         (2) Karma Ledger         — a signed integer ledger tracking moral debt and merit.
 *         (3) Social Recovery      — dual-guardian, time-locked wallet recovery.
 *         (4) Gasless Transactions — ERC-2771 meta-transaction support, gas absorbed by the service provider.
 *
 * @dev    Design decisions crystallised after audit review (V5):
 *
 *         GUARDIAN CONTROLS CANCEL  — cancelRecovery is intentionally restricted to guardians only.
 *           Rationale: in a small, trust-based community the probability of two independent guardians
 *           colluding or being compromised simultaneously is considered lower than the probability of
 *           an owner's private key being stolen. The 48-hour (or custom) time-lock gives the owner
 *           the reaction window; off-chain notifications bridge the remaining gap.
 *
 *         AUTO-HEARTBEAT IN addKarma — lastActiveTime is updated automatically when karma changes.
 *           Rationale: GAME_ROLE is exclusively held by service-controlled contracts. The griefing
 *           vector (a compromised bot locking out recovery via forced heartbeats) is accepted as a
 *           managed risk given the trust boundary. Re-evaluate if GAME_ROLE is ever granted to
 *           third-party dApps.
 *
 *         REINCARNATION TAX (1.33x on negative karma) — intentional, non-zero-sum design.
 *           Rationale: users cannot escape karmic debt by triggering social recovery. The amplified
 *           penalty makes guardians naturally reluctant to recover accounts with heavy negative karma,
 *           acting as a decentralised deterrent without requiring explicit contract-level gates.
 *           Systemic karma drift toward negative is a deliberate game-theory property.
 *
 *         GASLESS via TRUSTED FORWARDER — address(0) is allowed for setTrustedForwarder.
 *           Rationale: the forwarder is internal infrastructure managed by the service provider.
 *           Setting it to address(0) effectively disables gasless support; no explicit guard needed
 *           because admin access is already role-gated.
 *
 *         KARMA BOUNDS CLAMP in _processRecovery — recovery-time karma redistribution is clamped
 *           to ±100_000 to maintain consistency with the addKarma boundary, regardless of the
 *           1.33x amplification on negative karma.
 */
contract PIF12 is
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
    /// @dev Authorized service-controlled bots. Grant to third-party dApps only after re-evaluating
    ///      the auto-heartbeat risk in addKarma.
    bytes32 public constant GAME_ROLE     = keccak256("GAME_ROLE");

    // ==========================================
    // Time Constants
    // ==========================================

    /// @dev Minimum delay a guardian must wait between initiating and executing recovery.
    ///      Also used as the fixed time-lock for guardian-change and opt-out requests.
    uint256 public constant MIN_RECOVERY_DELAY = 48 hours;

    /// @dev Upper ceiling for user-customisable recovery delay. High-value accounts should
    ///      set this to the maximum for the strongest protection.
    uint256 public constant MAX_RECOVERY_DELAY = 30 days;

    /// @dev Fallback delay applied when the owner has never called setRecoveryDelay.
    uint256 public constant DEFAULT_RECOVERY_DELAY = 48 hours;

    /// @dev If the owner's lastActiveTime is within this window, extra delay is added on top
    ///      of their custom delay (additive, not max-based) to protect clearly active accounts.
    uint256 public constant ACTIVE_WINDOW = 14 days;

    /// @dev Extra seconds added to the required recovery delay when the owner is recently active.
    ///      Example: custom delay = 30 days + active bonus = 37 days total.
    uint256 public constant ACTIVE_ACCOUNT_EXTENDED_DELAY = 7 days;

    // ==========================================
    // Karma Bounds
    // ==========================================

    int256 public constant KARMA_MAX =  100_000;
    int256 public constant KARMA_MIN = -100_000;

    // ==========================================
    // State Variables
    // ==========================================

    /// @dev The Pay-It-Forward ledger. Positive = merit, negative = karmic debt.
    mapping(address => int256) public karmaPoints;

    struct GuardianSet {
        address guardianA;
        address guardianB;
    }
    /// @dev Active guardian pairs per wallet.
    mapping(address => GuardianSet) public customGuardians;

    struct PendingGuardianChange {
        GuardianSet newGuardians;
        uint256 effectiveTime; // Timestamp after which executeGuardianChange may be called.
    }
    /// @dev Staged guardian changes awaiting their 48-hour time-lock.
    mapping(address => PendingGuardianChange) public pendingGuardianChanges;

    struct RecoveryRequest {
        address targetWallet;   // Destination wallet for the SBT.
        address firstApprover;  // Guardian who initiated; the other guardian must execute.
        uint256 initiatedAt;    // Timestamp used to enforce the execution time-lock.
    }
    /// @dev oldWallet => tokenId => pending recovery request.
    mapping(address => mapping(uint256 => RecoveryRequest)) public pendingRecoveries;

    /// @dev Tracks the last recovery timestamp for the 6-month cooldown and 30-day privilege freeze.
    mapping(address => uint256) public lastRecoveryTime;

    /// @dev User-defined execution delay for recovery. Falls back to DEFAULT_RECOVERY_DELAY if zero.
    mapping(address => uint256) public recoveryDelay;

    /// @dev Updated by heartbeat() and by addKarma() (auto-heartbeat). Used to detect active accounts
    ///      and apply ACTIVE_ACCOUNT_EXTENDED_DELAY on top of the base recovery delay.
    mapping(address => uint256) public lastActiveTime;

    // --- Lone Wolf Mode ---
    /// @dev When true, admin-initiated recovery is permanently blocked for this wallet.
    ///      The wallet must have custom guardians set before opting out.
    mapping(address => bool) public adminRecoveryOptOut;

    struct PendingOptOutRequest {
        bool requestedStatus;  // The desired opt-out value once the time-lock expires.
        uint256 effectiveTime;
    }
    mapping(address => PendingOptOutRequest) public pendingOptOuts;

    // --- Gasless Meta-Transactions (ERC-2771) ---
    /// @dev The trusted forwarder contract that prepends the original sender's address to calldata.
    ///      Gas costs are absorbed by the service provider. Setting to address(0) disables gasless.
    address public trustedForwarder;

    // ==========================================
    // Events
    // ==========================================
    event KarmaUpdated(address indexed user, int256 delta, int256 newTotal);

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
    // Constructor
    // ==========================================
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ==========================================
    // Initialiser
    // ==========================================
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

    /**
     * @notice Update the trusted forwarder address.
     * @dev    Setting to address(0) disables gasless support.
     *         No zero-address guard is intentional — the forwarder is internal infrastructure
     *         and this function is already protected by DEFAULT_ADMIN_ROLE.
     */
    function setTrustedForwarder(address _forwarder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit TrustedForwarderUpdated(trustedForwarder, _forwarder);
        trustedForwarder = _forwarder;
    }

    function isTrustedForwarder(address forwarder) public view returns (bool) {
        return forwarder == trustedForwarder;
    }

    /**
     * @dev If called through the trusted forwarder, extract the original signer from the last
     *      20 bytes of calldata (ERC-2771 convention). Otherwise behave as a standard call.
     *      This makes every function that uses _msgSender() automatically gasless-compatible.
     */
    function _msgSender()
        internal view virtual
        override(ContextUpgradeable)
        returns (address sender)
    {
        if (isTrustedForwarder(msg.sender) && msg.data.length >= 20) {
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return super._msgSender();
        }
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
    // Heartbeat & Custom Recovery Delay
    // ==========================================

    /**
     * @notice Set a custom execution delay for guardian recoveries on your account.
     * @dev    Must be between MIN_RECOVERY_DELAY (48h) and MAX_RECOVERY_DELAY (30d).
     *         If never called, DEFAULT_RECOVERY_DELAY applies automatically.
     *         High-value accounts should set this to MAX_RECOVERY_DELAY.
     */
    function setRecoveryDelay(uint256 delayInSeconds) external whenNotPaused {
        require(
            delayInSeconds >= MIN_RECOVERY_DELAY && delayInSeconds <= MAX_RECOVERY_DELAY,
            "Recovery: Delay must be between 48 hours and 30 days"
        );
        recoveryDelay[_msgSender()] = delayInSeconds;
        emit RecoveryDelayUpdated(_msgSender(), delayInSeconds);
    }

    /**
     * @notice Returns the effective recovery delay for a given wallet.
     * @dev    Returns the user's custom value if set; otherwise DEFAULT_RECOVERY_DELAY.
     */
    function getRecoveryDelay(address user) public view returns (uint256) {
        uint256 custom = recoveryDelay[user];
        return custom > 0 ? custom : DEFAULT_RECOVERY_DELAY;
    }

    /**
     * @notice Prove that you are in control of your wallet.
     * @dev    Updates lastActiveTime. If a recovery is initiated within ACTIVE_WINDOW (14 days)
     *         after this call, ACTIVE_ACCOUNT_EXTENDED_DELAY (7 days) is added on top of the
     *         base delay, giving the owner more time to detect and react.
     *         Calling this weekly is recommended for active users.
     *         Note: addKarma also triggers an auto-heartbeat when GAME_ROLE bots update karma,
     *         which is acceptable given GAME_ROLE is service-controlled infrastructure.
     */
    function heartbeat() external whenNotPaused {
        lastActiveTime[_msgSender()] = block.timestamp;
        emit Heartbeat(_msgSender(), block.timestamp);
    }

    /// @notice Returns true if the wallet has been active within ACTIVE_WINDOW.
    function isRecentlyActive(address user) public view returns (bool) {
        return block.timestamp < lastActiveTime[user] + ACTIVE_WINDOW;
    }

    // ==========================================
    // Karma (Pay It Forward) System
    // ==========================================

    /// @notice Returns true if the wallet is within the 30-day privilege freeze after recovery.
    function isPrivilegeFrozen(address user) public view returns (bool) {
        return block.timestamp < lastRecoveryTime[user] + 30 days;
    }

    /**
     * @notice Add or subtract karma points for a user. Only callable by GAME_ROLE.
     * @dev    Auto-heartbeat: also updates lastActiveTime so that active players are protected
     *         by ACTIVE_ACCOUNT_EXTENDED_DELAY without needing to call heartbeat() manually.
     *         Re-evaluate if GAME_ROLE is ever granted to third-party contracts.
     */
    function addKarma(address user, int256 points) external onlyRole(GAME_ROLE) whenNotPaused {
        require(!isPrivilegeFrozen(user), "PIF12: User privileges are frozen for 30 days");

        int256 newTotal = karmaPoints[user] + points;
        require(newTotal >= KARMA_MIN && newTotal <= KARMA_MAX, "PIF12: Karma out of bounds");

        karmaPoints[user] = newTotal;
        lastActiveTime[user] = block.timestamp; // Auto-heartbeat triggered by engagement.

        emit KarmaUpdated(user, points, newTotal);
    }

    // ==========================================
    // Lone Wolf Mode (Opt-out of Admin Recovery)
    // ==========================================

    /**
     * @notice Request to change your admin-recovery opt-out status.
     * @dev    Staged with a MIN_RECOVERY_DELAY time-lock to prevent impulsive or coerced changes.
     *         Recommended: set custom guardians before opting out of admin recovery.
     */
    function requestAdminRecoveryOptOut(bool optOut) external whenNotPaused {
        uint256 effectiveTime = block.timestamp + MIN_RECOVERY_DELAY;
        pendingOptOuts[_msgSender()] = PendingOptOutRequest(optOut, effectiveTime);
        emit AdminRecoveryOptOutRequested(_msgSender(), optOut, effectiveTime);
    }

    /// @notice Cancel a pending opt-out request before it takes effect.
    function cancelAdminRecoveryOptOut() external whenNotPaused {
        require(pendingOptOuts[_msgSender()].effectiveTime != 0, "Recovery: No pending opt-out request");
        delete pendingOptOuts[_msgSender()];
        emit AdminRecoveryOptOutCancelled(_msgSender());
    }

    /// @notice Execute a pending opt-out request after the time-lock has expired.
    function executeAdminRecoveryOptOut() external whenNotPaused {
        PendingOptOutRequest memory req = pendingOptOuts[_msgSender()];
        require(req.effectiveTime != 0, "Recovery: No pending opt-out request");
        require(block.timestamp >= req.effectiveTime, "Recovery: Time-lock not expired yet");

        adminRecoveryOptOut[_msgSender()] = req.requestedStatus;
        delete pendingOptOuts[_msgSender()];
        emit AdminRecoveryOptOutExecuted(_msgSender(), req.requestedStatus);
    }

    // ==========================================
    // Guardian Management
    // ==========================================

    /**
     * @notice Request to replace your guardian pair.
     * @dev    Fixed 48-hour time-lock (MIN_RECOVERY_DELAY), regardless of custom recovery delay
     *         or heartbeat status. Rationale: guardian replacement is an emergency action
     *         (e.g., a guardian key is compromised). Applying the longer dynamic delay would
     *         leave the user exposed during the extended waiting period.
     */
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

    /// @notice Cancel a pending guardian change before it takes effect.
    function cancelGuardianChange() external whenNotPaused {
        require(pendingGuardianChanges[_msgSender()].effectiveTime != 0, "Recovery: No pending change");
        delete pendingGuardianChanges[_msgSender()];
        emit GuardianChangeCancelled(_msgSender());
    }

    /// @notice Execute a pending guardian change after the 48-hour time-lock has expired.
    function executeGuardianChange() external whenNotPaused {
        PendingGuardianChange memory pending = pendingGuardianChanges[_msgSender()];
        require(pending.effectiveTime != 0,              "Recovery: No pending guardian change");
        require(block.timestamp >= pending.effectiveTime, "Recovery: Time-lock not expired yet");

        customGuardians[_msgSender()] = pending.newGuardians;
        delete pendingGuardianChanges[_msgSender()];
        emit GuardiansSet(_msgSender(), pending.newGuardians.guardianA, pending.newGuardians.guardianB);
    }

    // ==========================================
    // Social Recovery Execution
    // ==========================================

    /**
     * @notice Admin-forced recovery for wallets that have not set custom guardians.
     * @dev    Blocked if the owner has opted out (Lone Wolf Mode) or has set custom guardians.
     *         Karma penalty: owner keeps only 1/3; the remaining 2/3 are burned.
     */
    function adminRecoverWallet(address oldWallet, address newWallet, uint256 tokenId)
        external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused
    {
        require(!adminRecoveryOptOut[oldWallet],               "Recovery: User opted out of Admin recovery (Lone Wolf)");
        require(customGuardians[oldWallet].guardianA == address(0), "Recovery: User has custom guardians, Admin locked out");
        _processRecovery(oldWallet, newWallet, tokenId, address(0), address(0));
        emit RecoveryExecuted(oldWallet, newWallet, tokenId);
    }

    /**
     * @notice Step 1: A guardian initiates a recovery request.
     * @dev    - Verifies oldWallet holds the SBT (prevents gas-wasting phantom requests).
     *         - Prevents overwriting an existing request (anti-griefing).
     *         - The initiating guardian cannot also execute (dual-signature requirement).
     */
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

    /**
     * @notice Cancel a pending recovery request.
     * @dev    INTENTIONALLY restricted to guardians only. The owner cannot cancel.
     *
     *         Design rationale: in a small, trust-based community the probability of two
     *         independent guardians colluding is considered lower than the probability of the
     *         owner's private key being stolen. If the owner's key is compromised, allowing
     *         the attacker to cancel a legitimate rescue would be more dangerous than the
     *         guardian-collusion scenario. The time-lock window is the owner's safety net;
     *         off-chain notifications bridge the remaining reaction gap.
     */
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

    /**
     * @notice Step 2: The second guardian confirms and executes the recovery.
     * @dev    Dynamic execution delay (additive):
     *           requiredDelay = getRecoveryDelay(oldWallet)
     *                         + (isRecentlyActive ? ACTIVE_ACCOUNT_EXTENDED_DELAY : 0)
     *         Example: custom = 30d, active = true → 30d + 7d = 37d total.
     *         This is additive (not max-based) so the active-account bonus always adds protection
     *         on top of whatever delay the owner has configured.
     */
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

        // Additive dynamic delay: base + active-account bonus.
        uint256 requiredDelay = getRecoveryDelay(oldWallet);
        if (isRecentlyActive(oldWallet)) {
            requiredDelay += ACTIVE_ACCOUNT_EXTENDED_DELAY;
        }
        require(
            block.timestamp >= req.initiatedAt + requiredDelay,
            "Recovery: Execution time-lock has not expired yet"
        );

        delete pendingRecoveries[oldWallet][tokenId];
        _processRecovery(oldWallet, newWallet, tokenId, guards.guardianA, guards.guardianB);
        emit RecoveryExecuted(oldWallet, newWallet, tokenId);
    }

    // ==========================================
    // Core Recovery Logic — The Reincarnation Tax
    // ==========================================

    /**
     * @dev Internal function: burns the SBT from the old wallet, mints to the new wallet,
     *      and redistributes karma according to the following rules:
     *
     *      POSITIVE KARMA (merit) — Shared Fate:
     *        Each party (newWallet, guardianA, guardianB) receives 1/3 of the original karma.
     *        Guardian B absorbs the integer division remainder to prevent precision loss.
     *        Karma is conserved: total distributed == total original.
     *
     *      NEGATIVE KARMA (debt) — Reincarnation Tax (intentionally non-zero-sum):
     *        newWallet  : oldKarma * 4/3  (amplified penalty, e.g. -300 → -400)
     *        guardianA  : oldKarma / 3    (e.g. -300 → -100)
     *        guardianB  : remainder        (e.g. -300 → -100)
     *        Total distributed: -600 from original -300.
     *        This systemic negative drift is a deliberate game-theory property:
     *          (a) Users cannot escape karmic debt by triggering recovery.
     *          (b) Guardians bear a share of the debt, naturally deterring them from
     *              recovering wallets with heavy negative karma.
     *
     *      ADMIN RECOVERY (no guardians):
     *        Positive karma: newWallet keeps 1/3; 2/3 burned.
     *        Negative karma: newWallet takes 4/3 amplified penalty; no guardian distribution.
     *
     *      All karma assignments are clamped to [KARMA_MIN, KARMA_MAX] for consistency
     *      with the addKarma boundary, regardless of amplification.
     */
    function _processRecovery(
        address oldWallet,
        address newWallet,
        uint256 tokenId,
        address guardA,
        address guardB
    ) internal {
        // Prevent accidentally freezing an already-active account.
        require(balanceOf(newWallet, tokenId) == 0, "Recovery: Target wallet already holds this SBT");

        // 6-month cooldown prevents abuse of the recovery mechanism.
        // Both wallets are checked to prevent cycling attacks (V6 fix).
        require(
            block.timestamp >= lastRecoveryTime[oldWallet] + 180 days,
            "Recovery: Old wallet cannot be recovered again within 6 months"
        );
        require(
            block.timestamp >= lastRecoveryTime[newWallet] + 180 days,
            "Recovery: New wallet cannot accept recovery within 6 months"
        );

        uint256 balance = balanceOf(oldWallet, tokenId);
        require(balance > 0, "Recovery: No tokens to recover");

        // SBT migration via Burn & Mint (bypasses the Soulbound transfer lock).
        _burn(oldWallet, tokenId, balance);
        _mint(newWallet, tokenId, balance, "");

        // Karma redistribution.
        int256 oldKarma = karmaPoints[oldWallet];

        if (oldKarma > 0) {
            // Positive karma: conserved, split into thirds.
            if (guardA != address(0)) {
                int256 split = oldKarma / 3;
                karmaPoints[newWallet] = _clampKarma(karmaPoints[newWallet] + split);
                karmaPoints[guardA]    = _clampKarma(karmaPoints[guardA]    + split);
                // Guard B absorbs the remainder (e.g. 100/3=33, remainder=1 goes to B).
                karmaPoints[guardB]    = _clampKarma(karmaPoints[guardB]    + (oldKarma - split - split));
            } else {
                // Admin recovery: user keeps 1/3, rest is burned.
                karmaPoints[newWallet] = _clampKarma(karmaPoints[newWallet] + oldKarma / 3);
            }

        } else if (oldKarma < 0) {
            // Negative karma: Reincarnation Tax — amplified penalty, non-zero-sum by design.
            if (guardA != address(0)) {
                int256 userPenalty  = (oldKarma * 4) / 3; // 1.33x amplified (e.g. -300 → -400).
                int256 guardPenalty = oldKarma / 3;        // Each guardian bears 1/3 (e.g. → -100).

                karmaPoints[newWallet] = _clampKarma(karmaPoints[newWallet] + userPenalty);
                karmaPoints[guardA]    = _clampKarma(karmaPoints[guardA]    + guardPenalty);
                karmaPoints[guardB]    = _clampKarma(karmaPoints[guardB]    + (oldKarma - guardPenalty - guardPenalty));
            } else {
                // Admin recovery: user absorbs the full 1.33x penalty alone.
                karmaPoints[newWallet] = _clampKarma(karmaPoints[newWallet] + (oldKarma * 4) / 3);
            }
        }
        // Zero karma: no redistribution needed.

        karmaPoints[oldWallet] = 0;

        // Start the 6-month cooldown and 30-day privilege freeze on both wallets.
        // Freezing the old wallet also prevents it from being recycled immediately.
        lastRecoveryTime[newWallet] = block.timestamp;
        lastRecoveryTime[oldWallet] = block.timestamp;
    }

    /**
     * @dev Clamp a karma value to [KARMA_MIN, KARMA_MAX].
     *      Applied after every karma assignment in _processRecovery to ensure that recovery-time
     *      amplification (Reincarnation Tax) never produces values outside the declared bounds.
     */
    function _clampKarma(int256 value) internal pure returns (int256) {
        if (value > KARMA_MAX) return KARMA_MAX;
        if (value < KARMA_MIN) return KARMA_MIN;
        return value;
    }

    // ==========================================
    // Soulbound Lock Mechanism
    // ==========================================

    /**
     * @dev Overrides the ERC-1155 internal transfer hook.
     *      Minting (from == 0) and burning (to == 0) are always permitted.
     *      All other transfers are permanently locked; only DEFAULT_ADMIN_ROLE provides
     *      a strict escape hatch for critical backend migrations if ever necessary.
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155Upgradeable, ERC1155PausableUpgradeable, ERC1155SupplyUpgradeable) {
        if (from != address(0) && to != address(0)) {
            require(
                hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
                "PIF12: Transfers are locked. Tokens are Soulbound."
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
    // Reserve 50 slots to prevent storage collision when new state variables are added
    // in future upgrades. Adjust this value down as new variables consume slots.
    uint256[50] private __gap;
}
