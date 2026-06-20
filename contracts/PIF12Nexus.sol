// SPDX-License-Identifier: GPL-3.0-or-later
//
// PIF12Nexus — PIF12 (Pay It Forward, 12-Year Legacy)
// Copyright (C) 2026 Jason J. Lai
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
// This product includes software from OpenZeppelin (OpenZeppelin Contracts
// Upgradeable, MIT License, Copyright (c) OpenZeppelin). See the NOTICE file.
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title  PIF12Nexus v1.0.0 — PIF12 (Pay It Forward, 12-Year Legacy) "Curator Network"
 * @notice A 12-year Web3 social experiment on Ethereum L1. V8 pivots from a
 *         single-issuer blessing ledger (V7) to a FEDERATED CURATOR NETWORK,
 *         themed as a growing constellation of trust:
 *
 *         Naming: code uses the neutral concept term "Curator"; user-facing brand
 *         names are Lightkeeper (EN) / 小太陽 (ZH) for Layer 1 and Star / 星星 for
 *         Layer 2. The Initiator is 發起人 Jason.
 *
 *           發起人 Jason (Initiator)  — the origin point (GAME_ROLE relay + admin).
 *           Layer 1 — Curator        : the Initiator mints a zodiac-year token to
 *                                      a Curator. Brand: Lightkeeper (EN) / 小太陽 (ZH).
 *           Layer 2 — Star / 星星     : each Curator may issue Star SBTs to people
 *                                      they admire. The network stops at two
 *                                      layers — Stars cannot sub-issue.
 *
 * @dev V8 DESIGN PRINCIPLES (vs V7 NeoPIF):
 *
 *      1) NO NUMERIC VALUE — UNIQUE-PEOPLE COUNTING ONLY
 *         V5/V6 karma and V7 "PIF value" are removed entirely. There is no
 *         score, amount, cap, or cooldown on value. The only social metrics are
 *         two unique-person counters:
 *           peopleHelped[a]   — how many DISTINCT people `a` has helped
 *           peopleHelpedBy[a] — how many DISTINCT people have helped `a`
 *         Counting people (人數) rather than events (人次) is inherently
 *         sybil-resistant: A helping B 100 times still counts as 1. Inflating a
 *         counter requires recruiting many DISTINCT consenting SBT holders, so
 *         the attack cost scales with real social graph size, not transactions.
 *
 *      2) CURATOR-DRIVEN ISSUANCE (NO INITIATOR SIGNATURE PER STAR)
 *         A Curator calls issuePersonalSBT() themselves (gaslessly via the
 *         trusted forwarder; the Paymaster pays). The Initiator never co-signs an
 *         individual Star. The Initiator's only minting role is the Layer-1
 *         Curator relay.
 *
 *      3) GASLESS BY DEFAULT (ERC-2771 + Paymaster)
 *         Curators and recipients never touch ETH. All user-facing entry points
 *         resolve the actor via _msgSender(), so a trusted forwarder can relay
 *         meta-transactions funded by a Paymaster budget.
 *
 *      4) CO-ATTESTED MUTUAL AID (CONSENT REQUIRED)
 *         recordHelp(recipient) creates a pending record; confirmHelp(id, memo)
 *         is called by the recipient. A counter only moves on the FIRST
 *         confirmed help for a given (giver, recipient) ordered pair. A free-text
 *         memo is emitted in the event log only (never stored, never validated
 *         on-chain) — the front-end is the moderation/rendering layer. On-chain
 *         log content is permanent and public by design.
 *
 *      5) SOCIAL RECOVERY — ADMIN DEFAULT, USER MAY OPT OUT
 *         Every member is recoverable by the Initiator (admin wallet) by
 *         default — no setup required (recoveryMode == Unset resolves to
 *         AdminDefault). A member may opt out by changing their mode to:
 *           Guardian — two designated guardians who must BOTH be network members,
 *                      dual-approval + timelock.
 *           LoneWolf — nobody can recover; the wallet is final.
 *         Changing recovery mode is time-locked, so an attacker who briefly
 *         controls a wallet cannot instantly lock out admin recovery. Recovery
 *         migrates the whole identity (tokens supplied as a list + counters +
 *         Curator status + quota + recovery config) to a new wallet.
 *
 *      6) TIME-BOUND INDUCTION, GRACE-PROTECTED ISSUANCE
 *         A Curator can only be INDUCTED during their zodiac year's [start,
 *         deadline] window. Once inducted, their right to issue Stars stays open
 *         until max(their year's deadline, inductionTime + CURATOR_GRACE_PERIOD)
 *         — so a Curator inducted late in the year still gets a 100-day grace to
 *         curate. Windows are arbitrary timestamps (no calendar is hard-coded),
 *         so the Initiator may, e.g., open on a Gregorian boundary and close on
 *         the lunar new year.
 *
 *      7) SOULBOUND
 *         All tokens are non-transferable. Mint and burn are allowed; the
 *         admin retains a transfer escape hatch as a last-resort fix (e.g. for a
 *         token stranded by a partial recovery list).
 *
 *      RELEASE: This is v1.0.0 — the FIRST shipped version of PIF12. It descends
 *      from internal design iterations (karma ledger V5/V6 → PIF-value V7 →
 *      Curator Network) but ships as v1: all numeric value (karma/PIF) is removed
 *      in favor of unique-people counting, and it is licensed GPL-3.0-or-later
 *      (copyleft, not MIT). The earlier draft numbers were never deployed.
 *
 *      AUDIT NOTE: v1.0.0 is a FRESH deployment, not a UUPS upgrade of any prior
 *      draft — the storage layout is new. Requires a fresh security audit before
 *      mainnet. Future evolution ships as UUPS upgrades (v1.1, v2.0, …).
 */
contract PIF12Nexus is
    ERC1155Upgradeable,
    AccessControlUpgradeable,
    ERC1155PausableUpgradeable,
    ERC1155SupplyUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // ==========================================
    // Roles
    // ==========================================

    /// @dev Held by the contract admin (the Initiator) — a single founder wallet
    ///      at launch, with planned migration to a community multisig as core
    ///      members emerge. Controls upgrades, year windows, curator revocation,
    ///      forwarder/URI config, pause, and AdminDefault recovery.
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");

    /// @dev Held by the operational relay wallet (single key). May mint Curator
    ///      tokens (Layer 1) after off-chain claim verification, and acts as the
    ///      Paymaster-funded operator. Intentionally narrow: GAME_ROLE CANNOT
    ///      upgrade, change recovery, revoke curators, or move tokens. If the key
    ///      is compromised the admin can revoke it; the blast radius is "mint
    ///      spurious Curator tokens," which is recoverable via burn + revoke.
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");

    // ==========================================
    // Version
    // ==========================================

    /// @notice Semantic version of this implementation. v1.0.0 is the first
    ///         shipped version of PIF12 (karma removed → unique-people counting;
    ///         GPL-3.0 copyleft). Bumped on each UUPS upgrade.
    string public constant VERSION = "1.0.0";

    // ==========================================
    // Constants — Token Scheme & Quotas
    // ==========================================

    /// @dev Zodiac year tokens occupy ids 1..12 (shared id, supply == curators).
    uint8 public constant GENESIS_YEAR_COUNT = 12;

    /// @dev Personal (Star) SBT token ids start here; each is a unique id, supply 1.
    uint256 public constant PERSONAL_TOKEN_ID_START = 100;

    /// @dev Maximum Stars a single Curator may issue across the experiment.
    uint16 public constant PERSONAL_QUOTA = 50;

    /// @dev A Curator's right to issue Stars stays open until at least this long
    ///      after their induction, even past their zodiac year's deadline — so a
    ///      Curator inducted late in the year is not starved of time to curate.
    uint256 public constant CURATOR_GRACE_PERIOD = 100 days;

    /// @dev Byte caps for free-text fields. Bound gas and abuse surface. Content
    ///      is never validated on-chain; the front-end moderates display.
    uint256 public constant MAX_MESSAGE_BYTES = 256;
    uint256 public constant MAX_CID_BYTES     = 128;

    // ==========================================
    // Constants — Recovery Timing
    // ==========================================

    uint256 public constant MIN_RECOVERY_DELAY      = 48 hours;
    uint256 public constant MAX_RECOVERY_DELAY      = 30 days;
    uint256 public constant DEFAULT_RECOVERY_DELAY  = 48 hours;
    uint256 public constant RECOVERY_CHANGE_TIMELOCK = 48 hours;

    /// @dev Activity bonus: a recently-active wallet gets extra delay on top of
    ///      its base recovery delay, so a recovery cannot quietly complete while
    ///      the wallet is still in active use.
    uint256 public constant ACTIVE_WINDOW          = 14 days;
    uint256 public constant ACTIVE_EXTENDED_DELAY  = 7 days;

    /// @dev A wallet cannot be the source/target of recovery again within this
    ///      window — prevents recovery ping-pong abuse.
    uint256 public constant RECOVERY_REPEAT_COOLDOWN = 180 days;

    /// @dev A pending help record expires if not confirmed within this window.
    uint256 public constant HELP_CONFIRMATION_WINDOW = 30 days;

    // ==========================================
    // Types
    // ==========================================

    /// @dev Unset is the implicit default and resolves to AdminDefault (see
    ///      effectiveRecoveryMode). A member opts out by moving to Guardian or
    ///      LoneWolf via the time-locked change flow.
    enum RecoveryMode { Unset, AdminDefault, Guardian, LoneWolf }

    /// @dev Per-token identity record.
    ///      Year token : isYearToken=true, yearNumber=1..12, curator=address(0).
    ///      Star (pSBT): isYearToken=false, yearNumber=issuer's year,
    ///                   curator=issuer, seriesIndex=1..PERSONAL_QUOTA,
    ///                   customCID="" means "render the default year template".
    struct TokenInfo {
        bool    isYearToken;
        uint8   yearNumber;
        address curator;
        uint16  seriesIndex;
        string  customCID;
    }

    struct YearWindow {
        uint256 startTime;
        uint256 mintDeadline;
    }

    struct GuardianSet {
        address guardianA;
        address guardianB;
    }

    struct PendingRecoveryChange {
        RecoveryMode newMode;
        GuardianSet  newGuardians;
        uint256      effectiveTime;
    }

    struct PendingHelp {
        address giver;
        address recipient;
        uint256 createdAt;
        bool    exists;
    }

    struct RecoveryRequest {
        address targetWallet;
        address firstApprover;
        uint256 initiatedAt;
    }

    // ==========================================
    // State — Identity & Hierarchy
    // ==========================================

    mapping(uint256 => TokenInfo) public tokenInfo;

    /// @dev Next Star id to assign. Initialised to PERSONAL_TOKEN_ID_START.
    uint256 public nextPersonalTokenId;

    mapping(address => bool)  public isCurator;
    mapping(address => uint8) public curatorYear;

    /// @dev Timestamp a Curator was inducted. Anchors the 100-day issuance grace.
    mapping(address => uint256) public curatorSince;

    /// @dev Stars already issued by a Curator (quota usage).
    mapping(address => uint16) public personalSeriesIssued;

    /// @dev Prevents a Curator issuing more than one Star to the same recipient.
    mapping(address => mapping(address => bool)) public hasIssuedTo;

    /// @dev Per-holder token count (sum of balances across all ids), maintained
    ///      in _update. Enables O(1) "is this address a network member?" checks
    ///      without enumerating ERC-1155 ids.
    mapping(address => uint256) public heldTokenCount;

    mapping(uint8 => YearWindow) public yearWindows;

    // ==========================================
    // State — Mutual Aid (unique-people counting)
    // ==========================================

    mapping(address => uint256) public peopleHelped;
    mapping(address => uint256) public peopleHelpedBy;

    /// @dev hasHelped[giver][recipient] == true once that ordered pair's first
    ///      help has been confirmed. Gates counter increments to first-time only.
    mapping(address => mapping(address => bool)) public hasHelped;

    mapping(bytes32 => PendingHelp) public pendingHelp;

    /// @dev Append-only list of pending record ids per recipient. Front-end
    ///      filters by pendingHelp[id].exists (deletions are not pruned here).
    mapping(address => bytes32[]) public pendingHelpByRecipient;

    // ==========================================
    // State — Social Recovery
    // ==========================================

    mapping(address => RecoveryMode) public recoveryMode;     // Unset => AdminDefault
    mapping(address => GuardianSet)  public customGuardians;
    mapping(address => PendingRecoveryChange) public pendingRecoveryChanges;

    /// @dev oldWallet => the single in-flight recovery request.
    mapping(address => RecoveryRequest) public pendingRecoveries;

    mapping(address => uint256) public lastRecoveryTime;
    mapping(address => uint256) public recoveryDelay;   // 0 => DEFAULT_RECOVERY_DELAY
    mapping(address => uint256) public lastActiveTime;

    // ==========================================
    // State — Gasless
    // ==========================================

    address public trustedForwarder;

    // ==========================================
    // State — Stage Gate
    // ==========================================

    /// @dev Stage gate for Layer-2 (Star) issuance. Deploys false at Stage 1
    ///      (Curator claim only), so issuePersonalSBT is provably dormant. The
    ///      admin flips it true at Stage 2. This activates an already-written
    ///      feature via a single flag instead of a riskier contract upgrade.
    bool public issuanceEnabled;

    // ==========================================
    // Events
    // ==========================================

    event CuratorTokenMinted(address indexed to, uint8 indexed yearNumber, uint256 tokenId);
    event PersonalSBTIssued(
        address indexed curator,
        address indexed recipient,
        uint256 indexed tokenId,
        uint16  seriesIndex,
        string  customImageCID,
        string  message
    );

    event HelpRecorded(bytes32 indexed recordId, address indexed giver, address indexed recipient);
    event HelpConfirmed(bytes32 indexed recordId, address indexed giver, address indexed recipient, bool firstTimePair, string memo);
    event HelpCancelled(bytes32 indexed recordId, address indexed giver);
    event HelpExpired(bytes32 indexed recordId);

    event GuardiansSet(address indexed user, address guardianA, address guardianB);
    event RecoveryChangeRequested(address indexed user, RecoveryMode mode, address guardianA, address guardianB, uint256 effectiveTime);
    event RecoveryChangeCancelled(address indexed user);
    event RecoveryModeChanged(address indexed user, RecoveryMode mode);
    event RecoveryDelayUpdated(address indexed user, uint256 newDelay);

    event RecoveryInitiated(address indexed oldWallet, address indexed newWallet, address initiator);
    event RecoveryCancelled(address indexed oldWallet);
    event IdentityRecovered(
        address indexed oldWallet,
        address indexed newWallet,
        uint256 peopleHelpedMoved,
        uint256 peopleHelpedByMoved,
        bool    curatorMoved
    );

    event Heartbeat(address indexed user, uint256 timestamp);
    event CuratorRevoked(address indexed curator, string reason);
    event YearWindowSet(uint8 indexed yearNumber, uint256 startTime, uint256 mintDeadline);
    event TrustedForwarderUpdated(address indexed oldForwarder, address indexed newForwarder);
    event IssuanceEnabledSet(bool enabled);

    // ==========================================
    // Custom Errors (bytecode-efficient; replace revert strings)
    // ==========================================

    error ZeroAdmin();
    error ZeroOperator();
    error ZeroRecipient();
    error ZeroGuardian();
    error YearOutOfRange();
    error BadYearWindow();
    error YearWindowClosed();
    error AlreadyCurator();
    error AlreadyHoldsYearToken();
    error NotCurator();
    error IssuanceDisabled();
    error IssuanceWindowClosed();
    error SelfIssue();
    error QuotaExhausted();
    error AlreadyIssuedTo();
    error CidTooLong();
    error MessageTooLong();
    error SelfHelp();
    error GiverNotMember();
    error RecipientNotMember();
    error RecordCollision();
    error NoSuchRecord();
    error NotRecipient();
    error ConfirmWindowExpired();
    error NotGiver();
    error NotYetExpired();
    error DelayOutOfRange();
    error MustPickMode();
    error NoPendingChange();
    error TimelockNotExpired();
    error GuardiansSame();
    error SelfGuardian();
    error GuardianNotMember();
    error NotGuardianMode();
    error BadNewWallet();
    error RecoveryAlreadyPending();
    error NotAGuardian();
    error NoPendingRecovery();
    error NoRecoveryInitiated();
    error TargetMismatch();
    error NeedSecondGuardian();
    error NotAdminMode();
    error SameWallet();
    error OldInCooldown();
    error NewInCooldown();
    error OldLacksToken();
    error NewHoldsToken();
    error NewAlreadyCurator();
    error SoulboundTransferLocked();

    // ==========================================
    // Constructor / Initialiser
    // ==========================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @param defaultAdmin Admin wallet (Initiator) — gets DEFAULT_ADMIN_ROLE +
     *                      UPGRADER_ROLE + PAUSER_ROLE.
     * @param gameOperator Operational relay wallet — gets GAME_ROLE.
     * @param _forwarder   Trusted ERC-2771 forwarder (Paymaster-compatible).
     * @param baseURI      Base metadata URI, e.g. "ipfs://CID/{id}.json".
     */
    function initialize(
        address defaultAdmin,
        address gameOperator,
        address _forwarder,
        string memory baseURI
    ) external initializer {
        if (defaultAdmin == address(0)) revert ZeroAdmin();
        if (gameOperator == address(0)) revert ZeroOperator();

        __ERC1155_init(baseURI);
        __AccessControl_init();
        __ERC1155Pausable_init();
        __ERC1155Supply_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE,      defaultAdmin);
        _grantRole(PAUSER_ROLE,        defaultAdmin);
        _grantRole(GAME_ROLE,          gameOperator);

        trustedForwarder    = _forwarder;
        nextPersonalTokenId = PERSONAL_TOKEN_ID_START;
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
        }
        return super._msgData();
    }

    // ==========================================
    // Admin — Pause / Metadata / Year Windows
    // ==========================================

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    function setURI(string memory newuri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    /// @notice Per-token URI: returns a Star's custom image CID when set,
    ///         otherwise the base "{id}" URI (year templates / default art).
    function uri(uint256 id) public view override returns (string memory) {
        string memory cid = tokenInfo[id].customCID;
        if (bytes(cid).length > 0) {
            return cid;
        }
        return super.uri(id);
    }

    /**
     * @notice Set the open/close window for a zodiac year (ids 1..12).
     * @dev    Arbitrary timestamps; no calendar is hard-coded. mintDeadline must
     *         be strictly after startTime. The window gates Curator INDUCTION
     *         (mintCuratorToken). Star issuance is gated separately by
     *         curatorIssuanceDeadline (year deadline OR +100d grace, whichever later).
     */
    function setYearWindow(uint8 yearNumber, uint256 startTime, uint256 mintDeadline)
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (yearNumber < 1 || yearNumber > GENESIS_YEAR_COUNT) revert YearOutOfRange();
        if (mintDeadline <= startTime) revert BadYearWindow();
        yearWindows[yearNumber] = YearWindow(startTime, mintDeadline);
        emit YearWindowSet(yearNumber, startTime, mintDeadline);
    }

    function isYearOpen(uint8 yearNumber) public view returns (bool) {
        YearWindow memory w = yearWindows[yearNumber];
        return w.startTime != 0
            && block.timestamp >= w.startTime
            && block.timestamp <= w.mintDeadline;
    }

    // ==========================================
    // Layer 1 — Curator Induction (GAME_ROLE relay)
    // ==========================================

    /**
     * @notice Mint a zodiac-year token and elevate `to` to Curator (小太陽).
     * @dev    Called by the operational relay (GAME_ROLE) after off-chain claim
     *         verification — the recipient never signs an on-chain mint. The
     *         exact claim-link verification flow is handled off-chain and does
     *         not affect this interface.
     *
     *         One Curator token per identity (require !isCurator). Recovery is
     *         AdminDefault out of the box, so no recovery setup is required first.
     */
    function mintCuratorToken(address to, uint8 yearNumber)
        external onlyRole(GAME_ROLE) whenNotPaused nonReentrant
    {
        if (to == address(0)) revert ZeroRecipient();
        if (yearNumber < 1 || yearNumber > GENESIS_YEAR_COUNT) revert YearOutOfRange();
        if (!isYearOpen(yearNumber)) revert YearWindowClosed();
        if (isCurator[to]) revert AlreadyCurator();
        if (balanceOf(to, yearNumber) != 0) revert AlreadyHoldsYearToken();

        // Initialise the shared year-token record once.
        if (!tokenInfo[yearNumber].isYearToken) {
            tokenInfo[yearNumber] = TokenInfo({
                isYearToken: true,
                yearNumber:  yearNumber,
                curator:     address(0),
                seriesIndex: 0,
                customCID:   ""
            });
        }

        isCurator[to]    = true;
        curatorYear[to]  = yearNumber;
        curatorSince[to] = block.timestamp;

        _mint(to, yearNumber, 1, "");
        emit CuratorTokenMinted(to, yearNumber, yearNumber);
    }

    // ==========================================
    // Layer 2 — Curator Issues a Star (Personal SBT)
    // ==========================================

    /**
     * @notice The deadline by which a Curator may still issue Stars:
     *         max(their zodiac year's deadline, induction time + 100 days).
     */
    function curatorIssuanceDeadline(address curator) public view returns (uint256) {
        uint256 yearDeadline  = yearWindows[curatorYear[curator]].mintDeadline;
        uint256 graceDeadline = curatorSince[curator] + CURATOR_GRACE_PERIOD;
        return yearDeadline > graceDeadline ? yearDeadline : graceDeadline;
    }

    /**
     * @notice A Curator issues a Star (Personal SBT) to someone they admire.
     * @dev    Curator-driven and gasless: the Curator is _msgSender() (relayed
     *         via the forwarder, Paymaster-funded). The Initiator does NOT co-sign.
     *
     *         Two-layer stop: a Star does NOT make its recipient a Curator, so
     *         Stars cannot sub-issue.
     *
     *         Guards: caller is a (non-revoked) Curator; still within their
     *         issuance window (curatorIssuanceDeadline); has quota remaining; and
     *         has not already issued to this recipient. `message` is emitted in
     *         the log only — never stored, never validated on-chain.
     */
    function issuePersonalSBT(address recipient, string calldata customImageCID, string calldata message)
        external whenNotPaused nonReentrant
        returns (uint256 tokenId)
    {
        address curator = _msgSender();
        if (!issuanceEnabled) revert IssuanceDisabled();
        if (!isCurator[curator]) revert NotCurator();
        if (block.timestamp > curatorIssuanceDeadline(curator)) revert IssuanceWindowClosed();
        if (recipient == address(0)) revert ZeroRecipient();
        if (recipient == curator) revert SelfIssue();
        if (personalSeriesIssued[curator] >= PERSONAL_QUOTA) revert QuotaExhausted();
        if (hasIssuedTo[curator][recipient]) revert AlreadyIssuedTo();
        if (bytes(customImageCID).length > MAX_CID_BYTES) revert CidTooLong();
        if (bytes(message).length > MAX_MESSAGE_BYTES) revert MessageTooLong();

        hasIssuedTo[curator][recipient] = true;
        uint16 seriesIndex = personalSeriesIssued[curator] + 1;
        personalSeriesIssued[curator] = seriesIndex;

        tokenId = nextPersonalTokenId++;
        tokenInfo[tokenId] = TokenInfo({
            isYearToken: false,
            yearNumber:  curatorYear[curator],
            curator:     curator,
            seriesIndex: seriesIndex,
            customCID:   customImageCID
        });

        _mint(recipient, tokenId, 1, "");
        emit PersonalSBTIssued(curator, recipient, tokenId, seriesIndex, customImageCID, message);
    }

    // ==========================================
    // Mutual Aid — Co-Attested, Unique-People Counting
    // ==========================================

    /**
     * @notice Step 1: a giver records that they helped a recipient.
     * @dev    Both parties must be network members (hold any SBT). No counter
     *         moves until the recipient confirms. Repeated help between the same
     *         pair is allowed (e.g. to attach a fresh thank-you memo on confirm)
     *         but only the first confirmation ever moves a counter.
     */
    function recordHelp(address recipient)
        external whenNotPaused
        returns (bytes32 recordId)
    {
        address giver = _msgSender();
        if (recipient == address(0)) revert ZeroRecipient();
        if (recipient == giver) revert SelfHelp();
        if (heldTokenCount[giver] == 0) revert GiverNotMember();
        if (heldTokenCount[recipient] == 0) revert RecipientNotMember();

        recordId = keccak256(abi.encodePacked(giver, recipient, block.timestamp, block.number));
        if (pendingHelp[recordId].exists) revert RecordCollision();

        pendingHelp[recordId] = PendingHelp({
            giver:     giver,
            recipient: recipient,
            createdAt: block.timestamp,
            exists:    true
        });
        pendingHelpByRecipient[recipient].push(recordId);

        lastActiveTime[giver] = block.timestamp;
        emit HelpRecorded(recordId, giver, recipient);
    }

    /**
     * @notice Step 2: the recipient confirms the help.
     * @dev    Only the named recipient, within the confirmation window. On the
     *         first confirmed help for the (giver, recipient) pair, increments
     *         peopleHelped[giver] and peopleHelpedBy[recipient]. `memo` is a
     *         free-text thank-you emitted in the log only (front-end moderates).
     */
    function confirmHelp(bytes32 recordId, string calldata memo) external whenNotPaused {
        PendingHelp storage rec = pendingHelp[recordId];
        if (!rec.exists) revert NoSuchRecord();
        if (rec.recipient != _msgSender()) revert NotRecipient();
        if (block.timestamp > rec.createdAt + HELP_CONFIRMATION_WINDOW) revert ConfirmWindowExpired();
        if (bytes(memo).length > MAX_MESSAGE_BYTES) revert MessageTooLong();

        address giver     = rec.giver;
        address recipient = rec.recipient;

        bool firstTimePair = !hasHelped[giver][recipient];
        if (firstTimePair) {
            hasHelped[giver][recipient] = true;
            peopleHelped[giver]       += 1;
            peopleHelpedBy[recipient] += 1;
        }

        lastActiveTime[recipient] = block.timestamp;

        delete pendingHelp[recordId];
        emit HelpConfirmed(recordId, giver, recipient, firstTimePair, memo);
    }

    /// @notice Giver retracts a pending record before the recipient confirms.
    function cancelHelp(bytes32 recordId) external whenNotPaused {
        PendingHelp storage rec = pendingHelp[recordId];
        if (!rec.exists) revert NoSuchRecord();
        if (rec.giver != _msgSender()) revert NotGiver();
        emit HelpCancelled(recordId, rec.giver);
        delete pendingHelp[recordId];
    }

    /// @notice Anyone may prune an expired record (storage cleanup; no counters move).
    function pruneExpiredHelp(bytes32 recordId) external {
        PendingHelp storage rec = pendingHelp[recordId];
        if (!rec.exists) revert NoSuchRecord();
        if (block.timestamp <= rec.createdAt + HELP_CONFIRMATION_WINDOW) revert NotYetExpired();
        emit HelpExpired(recordId);
        delete pendingHelp[recordId];
    }

    function getPendingHelpForRecipient(address recipient) external view returns (bytes32[] memory) {
        return pendingHelpByRecipient[recipient];
    }

    // ==========================================
    // Heartbeat & Recovery Delay
    // ==========================================

    function heartbeat() external whenNotPaused {
        lastActiveTime[_msgSender()] = block.timestamp;
        emit Heartbeat(_msgSender(), block.timestamp);
    }

    function isRecentlyActive(address user) public view returns (bool) {
        return block.timestamp < lastActiveTime[user] + ACTIVE_WINDOW;
    }

    function setRecoveryDelay(uint256 delayInSeconds) external whenNotPaused {
        if (delayInSeconds < MIN_RECOVERY_DELAY || delayInSeconds > MAX_RECOVERY_DELAY) revert DelayOutOfRange();
        recoveryDelay[_msgSender()] = delayInSeconds;
        emit RecoveryDelayUpdated(_msgSender(), delayInSeconds);
    }

    function getRecoveryDelay(address user) public view returns (uint256) {
        uint256 custom = recoveryDelay[user];
        return custom > 0 ? custom : DEFAULT_RECOVERY_DELAY;
    }

    // ==========================================
    // Social Recovery — Admin Default, User May Opt Out
    // ==========================================

    /// @notice The recovery mode actually in force. Unset resolves to AdminDefault
    ///         — i.e. by default the Initiator (admin) can recover any member.
    function effectiveRecoveryMode(address user) public view returns (RecoveryMode) {
        RecoveryMode m = recoveryMode[user];
        return m == RecoveryMode.Unset ? RecoveryMode.AdminDefault : m;
    }

    /**
     * @notice Request a time-locked change to your recovery configuration.
     * @dev    Works from the default (Unset/AdminDefault) too. The timelock gives
     *         the real owner a window to react if an attacker who briefly controls
     *         the wallet tries to lock out admin recovery (e.g. by going LoneWolf).
     *         Guardian mode requires two distinct guardians that are BOTH network
     *         members and not the caller.
     */
    function requestRecoveryChange(RecoveryMode mode, address guardianA, address guardianB)
        external whenNotPaused
    {
        address user = _msgSender();
        if (mode == RecoveryMode.Unset) revert MustPickMode();

        GuardianSet memory g;
        if (mode == RecoveryMode.Guardian) {
            _validateGuardians(user, guardianA, guardianB);
            g = GuardianSet(guardianA, guardianB);
        }

        uint256 effectiveTime = block.timestamp + RECOVERY_CHANGE_TIMELOCK;
        pendingRecoveryChanges[user] = PendingRecoveryChange(mode, g, effectiveTime);
        emit RecoveryChangeRequested(user, mode, g.guardianA, g.guardianB, effectiveTime);
    }

    function cancelRecoveryChange() external whenNotPaused {
        if (pendingRecoveryChanges[_msgSender()].effectiveTime == 0) revert NoPendingChange();
        delete pendingRecoveryChanges[_msgSender()];
        emit RecoveryChangeCancelled(_msgSender());
    }

    function executeRecoveryChange() external whenNotPaused {
        address user = _msgSender();
        PendingRecoveryChange memory p = pendingRecoveryChanges[user];
        if (p.effectiveTime == 0) revert NoPendingChange();
        if (block.timestamp < p.effectiveTime) revert TimelockNotExpired();

        recoveryMode[user] = p.newMode;
        if (p.newMode == RecoveryMode.Guardian) {
            customGuardians[user] = p.newGuardians;
            emit GuardiansSet(user, p.newGuardians.guardianA, p.newGuardians.guardianB);
        } else {
            delete customGuardians[user];
        }

        delete pendingRecoveryChanges[user];
        emit RecoveryModeChanged(user, p.newMode);
    }

    function _validateGuardians(address user, address guardianA, address guardianB) internal view {
        if (guardianA == address(0) || guardianB == address(0)) revert ZeroGuardian();
        if (guardianA == guardianB) revert GuardiansSame();
        if (guardianA == user || guardianB == user) revert SelfGuardian();
        if (heldTokenCount[guardianA] == 0 || heldTokenCount[guardianB] == 0) revert GuardianNotMember();
    }

    // ==========================================
    // Social Recovery — Execution
    // ==========================================

    /**
     * @notice Guardian flow, step 1: a designated guardian initiates recovery to
     *         a fixed new wallet.
     */
    function initiateRecovery(address oldWallet, address newWallet)
        external whenNotPaused
    {
        if (recoveryMode[oldWallet] != RecoveryMode.Guardian) revert NotGuardianMode();
        if (newWallet == address(0) || newWallet == oldWallet) revert BadNewWallet();
        if (pendingRecoveries[oldWallet].firstApprover != address(0)) revert RecoveryAlreadyPending();

        GuardianSet memory g = customGuardians[oldWallet];
        if (_msgSender() != g.guardianA && _msgSender() != g.guardianB) revert NotAGuardian();

        pendingRecoveries[oldWallet] = RecoveryRequest(newWallet, _msgSender(), block.timestamp);
        emit RecoveryInitiated(oldWallet, newWallet, _msgSender());
    }

    function cancelRecovery(address oldWallet) external whenNotPaused {
        GuardianSet memory g = customGuardians[oldWallet];
        if (_msgSender() != g.guardianA && _msgSender() != g.guardianB) revert NotAGuardian();
        if (pendingRecoveries[oldWallet].firstApprover == address(0)) revert NoPendingRecovery();
        delete pendingRecoveries[oldWallet];
        emit RecoveryCancelled(oldWallet);
    }

    /**
     * @notice Guardian flow, step 2: the OTHER guardian executes after the
     *         time-lock, migrating the supplied tokens + the whole identity.
     * @dev    tokenIds MUST list every token the old wallet holds (derived from
     *         event-log indexing). Any omitted token stays on the old wallet; the
     *         admin transfer escape hatch can move stragglers if needed.
     */
    function executeRecovery(address oldWallet, address newWallet, uint256[] calldata tokenIds)
        external whenNotPaused nonReentrant
    {
        if (recoveryMode[oldWallet] != RecoveryMode.Guardian) revert NotGuardianMode();
        GuardianSet memory g = customGuardians[oldWallet];
        if (_msgSender() != g.guardianA && _msgSender() != g.guardianB) revert NotAGuardian();

        RecoveryRequest memory req = pendingRecoveries[oldWallet];
        if (req.firstApprover == address(0)) revert NoRecoveryInitiated();
        if (req.targetWallet != newWallet) revert TargetMismatch();
        if (req.firstApprover == _msgSender()) revert NeedSecondGuardian();

        uint256 requiredDelay = getRecoveryDelay(oldWallet);
        if (isRecentlyActive(oldWallet)) {
            requiredDelay += ACTIVE_EXTENDED_DELAY;
        }
        if (block.timestamp < req.initiatedAt + requiredDelay) revert TimelockNotExpired();

        delete pendingRecoveries[oldWallet];
        _processRecovery(oldWallet, newWallet, tokenIds);
    }

    /**
     * @notice AdminDefault flow: the Initiator (admin) recovers a wallet
     *         that is on the default mode (or explicitly AdminDefault).
     */
    function adminRecoverWallet(address oldWallet, address newWallet, uint256[] calldata tokenIds)
        external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant
    {
        if (effectiveRecoveryMode(oldWallet) != RecoveryMode.AdminDefault) revert NotAdminMode();
        if (newWallet == address(0) || newWallet == oldWallet) revert BadNewWallet();
        _processRecovery(oldWallet, newWallet, tokenIds);
    }

    /**
     * @dev Migrates tokens + identity state from old to new, then wipes old.
     *      LoneWolf wallets never reach here (neither admin nor guardian mode).
     *
     *      KNOWN LIMITATION (accepted): per-pair mappings cannot be enumerated,
     *      so hasHelped[old][*] and hasIssuedTo[old][*] are NOT migrated. After
     *      recovery a prior helper may count as a new unique pair, and the new
     *      wallet could re-issue to someone the old wallet already issued to (up
     *      to remaining quota). The 180-day repeat cooldown bounds exploitation.
     */
    function _processRecovery(address oldWallet, address newWallet, uint256[] calldata tokenIds) internal {
        if (newWallet == oldWallet) revert SameWallet();
        if (block.timestamp < lastRecoveryTime[oldWallet] + RECOVERY_REPEAT_COOLDOWN) revert OldInCooldown();
        if (block.timestamp < lastRecoveryTime[newWallet] + RECOVERY_REPEAT_COOLDOWN) revert NewInCooldown();

        // Migrate listed tokens via burn + mint (bypasses the soulbound lock).
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 id  = tokenIds[i];
            uint256 bal = balanceOf(oldWallet, id);
            if (bal == 0) revert OldLacksToken();
            if (balanceOf(newWallet, id) != 0) revert NewHoldsToken();
            _burn(oldWallet, id, bal);
            _mint(newWallet, id, bal, "");
        }

        // Migrate unique-people counters (additive on destination).
        uint256 helpedMoved   = peopleHelped[oldWallet];
        uint256 helpedByMoved = peopleHelpedBy[oldWallet];
        peopleHelped[newWallet]   += helpedMoved;
        peopleHelpedBy[newWallet] += helpedByMoved;
        peopleHelped[oldWallet]   = 0;
        peopleHelpedBy[oldWallet] = 0;

        // Migrate Curator status + quota + induction time.
        bool curatorMoved = isCurator[oldWallet];
        if (curatorMoved) {
            if (isCurator[newWallet]) revert NewAlreadyCurator();
            isCurator[newWallet]            = true;
            curatorYear[newWallet]          = curatorYear[oldWallet];
            curatorSince[newWallet]         = curatorSince[oldWallet];
            personalSeriesIssued[newWallet] = personalSeriesIssued[oldWallet];
            isCurator[oldWallet]            = false;
            curatorYear[oldWallet]          = 0;
            curatorSince[oldWallet]         = 0;
            personalSeriesIssued[oldWallet] = 0;
        }

        // Migrate recovery configuration so the new wallet keeps the same posture.
        recoveryMode[newWallet]    = recoveryMode[oldWallet];
        customGuardians[newWallet] = customGuardians[oldWallet];
        recoveryDelay[newWallet]   = recoveryDelay[oldWallet];
        recoveryMode[oldWallet]    = RecoveryMode.Unset;
        delete customGuardians[oldWallet];
        recoveryDelay[oldWallet]   = 0;

        // Start the repeat-cooldown on both wallets.
        lastRecoveryTime[oldWallet] = block.timestamp;
        lastRecoveryTime[newWallet] = block.timestamp;
        lastActiveTime[newWallet]   = block.timestamp;

        emit IdentityRecovered(oldWallet, newWallet, helpedMoved, helpedByMoved, curatorMoved);
    }

    // ==========================================
    // Admin — Curator Revocation
    // ==========================================

    /**
     * @notice Revoke a Curator's future issuance right.
     * @dev    Stars they already issued remain valid; the Curator keeps their
     *         (soulbound) year token. Only blocks further Star issuance. Admin
     *         only.
     */
    function revokeCurator(address curator, string calldata reason)
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (!isCurator[curator]) revert NotCurator();
        isCurator[curator] = false;
        emit CuratorRevoked(curator, reason);
    }

    /**
     * @notice Enable or disable Layer-2 (Star) issuance — the Year-1 → Year-2
     *         gate. Deploys false; the admin flips it true when the Star
     *         issuance frontend + gasless infra are live (planned Year 2).
     */
    function setIssuanceEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        issuanceEnabled = enabled;
        emit IssuanceEnabledSet(enabled);
    }

    // ==========================================
    // Views
    // ==========================================

    function getProfile(address user)
        external view
        returns (
            uint256 helped,         // distinct people this user has helped
            uint256 helpedBy,       // distinct people who have helped this user
            bool    curator,
            uint8   year,
            uint16  quotaUsed,
            uint16  quotaRemaining,
            RecoveryMode mode,      // effective mode (Unset resolved to AdminDefault)
            uint256 tokensHeld
        )
    {
        helped         = peopleHelped[user];
        helpedBy       = peopleHelpedBy[user];
        curator        = isCurator[user];
        year           = curatorYear[user];
        quotaUsed      = personalSeriesIssued[user];
        quotaRemaining = curator ? (PERSONAL_QUOTA - personalSeriesIssued[user]) : 0;
        mode           = effectiveRecoveryMode(user);
        tokensHeld     = heldTokenCount[user];
    }

    function isMember(address user) external view returns (bool) {
        return heldTokenCount[user] > 0;
    }

    // ==========================================
    // Soulbound Lock + Member-Count Bookkeeping
    // ==========================================

    /**
     * @dev Transfers between two non-zero holders are blocked (soulbound), except
     *      when triggered by the admin (escape hatch for stranded tokens).
     *      Mint (from==0) and burn (to==0) always pass the lock. After the parent
     *      hook applies balances, heldTokenCount is kept in sync.
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155Upgradeable, ERC1155PausableUpgradeable, ERC1155SupplyUpgradeable) {
        if (from != address(0) && to != address(0)) {
            if (!hasRole(DEFAULT_ADMIN_ROLE, _msgSender())) revert SoulboundTransferLocked();
        }

        super._update(from, to, ids, values);

        uint256 total;
        for (uint256 i = 0; i < values.length; i++) {
            total += values[i];
        }
        if (from != address(0)) {
            heldTokenCount[from] -= total;
        }
        if (to != address(0)) {
            heldTokenCount[to] += total;
        }
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
    // Storage Gap (fresh V8 deployment)
    // ==========================================
    // Reserved slots for future V8.x upgrades. V8 is a fresh deploy, so this need
    // not match V7's footprint — it only constrains later upgrades of V8 itself.
    uint256[38] private __gap;
}
