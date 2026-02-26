// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract PIF12 is ERC1155Upgradeable, AccessControlUpgradeable, ERC1155PausableUpgradeable, ERC1155SupplyUpgradeable, UUPSUpgradeable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE"); // Authorized dApp bots to manage Karma

    // ==========================================
    // Constants (防護時間參數)
    // ==========================================
    uint256 public constant MIN_RECOVERY_DELAY = 48 hours;
    uint256 public constant MAX_RECOVERY_DELAY = 30 days;
    uint256 public constant DEFAULT_RECOVERY_DELAY = 48 hours;
    uint256 public constant ACTIVE_WINDOW = 14 days;
    uint256 public constant ACTIVE_ACCOUNT_EXTENDED_DELAY = 7 days;

    // ==========================================
    // State Variables
    // ==========================================
    mapping(address => int256) public karmaPoints;

    struct GuardianSet {
        address guardianA;
        address guardianB;
    }
    mapping(address => GuardianSet) public customGuardians;

    struct PendingGuardianChange {
        GuardianSet newGuardians;
        uint256 effectiveTime;
    }
    mapping(address => PendingGuardianChange) public pendingGuardianChanges;

    struct RecoveryRequest {
        address targetWallet;
        address firstApprover;
        uint256 initiatedAt; 
    }
    mapping(address => mapping(uint256 => RecoveryRequest)) public pendingRecoveries; 

    // 狀態追蹤 Mappings
    mapping(address => uint256) public lastRecoveryTime;
    mapping(address => uint256) public recoveryDelay;   // 記錄用戶自訂的延遲時間
    mapping(address => uint256) public lastActiveTime;  // 記錄用戶最後活躍的心跳時間

    // ==========================================
    // Events
    // ==========================================
    event KarmaUpdated(address indexed user, int256 delta, int256 newTotal);
    event GuardianChangeRequested(address indexed user, address guardianA, address guardianB, uint256 effectiveTime);
    event GuardiansSet(address indexed user, address guardianA, address guardianB);
    event RecoveryInitiated(address indexed oldWallet, address indexed newWallet, uint256 tokenId, address initiator);
    event RecoveryExecuted(address indexed oldWallet, address indexed newWallet, uint256 tokenId);
    event RecoveryCancelled(address indexed oldWallet, uint256 tokenId);
    event RecoveryDelayUpdated(address indexed user, uint256 newDelay);
    event Heartbeat(address indexed user, uint256 timestamp);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address minter) initializer public {
        __ERC1155_init("ipfs://PENDING_URI/{id}.json");
        __AccessControl_init();
        __ERC1155Pausable_init();
        __ERC1155Supply_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(UPGRADER_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, defaultAdmin);
    }

    // ==========================================
    // Emergency Pause (Kill Switch)
    // ==========================================
    function pause() public onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() public onlyRole(PAUSER_ROLE) { _unpause(); }

    // ==========================================
    // Minting & Metadata Management
    // ==========================================
    function mintSBT(address to, uint256 id, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, id, amount, "");
    }

    function mintBatchSBT(address to, uint256[] memory ids, uint256[] memory amounts) public onlyRole(MINTER_ROLE) {
        _mintBatch(to, ids, amounts, "");
    }

    function setURI(string memory newuri) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    // ==========================================
    // Feature: Heartbeat & Custom Delay Functions
    // ==========================================
    function setRecoveryDelay(uint256 delayInSeconds) external whenNotPaused {
        require(delayInSeconds >= MIN_RECOVERY_DELAY && delayInSeconds <= MAX_RECOVERY_DELAY, "Recovery: Delay must be between 48 hours and 30 days");
        recoveryDelay[msg.sender] = delayInSeconds;
        emit RecoveryDelayUpdated(msg.sender, delayInSeconds);
    }

    function getRecoveryDelay(address user) public view returns (uint256) {
        uint256 customDelay = recoveryDelay[user];
        return customDelay > 0 ? customDelay : DEFAULT_RECOVERY_DELAY;
    }

    function heartbeat() external whenNotPaused {
        lastActiveTime[msg.sender] = block.timestamp;
        emit Heartbeat(msg.sender, block.timestamp);
    }

    function isRecentlyActive(address user) public view returns (bool) {
        return block.timestamp < lastActiveTime[user] + ACTIVE_WINDOW;
    }

    // ==========================================
    // Karma (Pay It Forward) System
    // ==========================================
    function isPrivilegeFrozen(address user) public view returns (bool) {
        return block.timestamp < lastRecoveryTime[user] + 30 days;
    }

    function addKarma(address user, int256 points) external onlyRole(GAME_ROLE) whenNotPaused {
        require(!isPrivilegeFrozen(user), "PIF12: User privileges are frozen for 30 days");

        int256 newTotal = karmaPoints[user] + points;
        require(newTotal >= -100000 && newTotal <= 100000, "PIF12: Karma out of bounds");

        karmaPoints[user] = newTotal;
        
        // 🟢 無感心跳：當用戶獲得或消耗陰德值時，自動更新活躍時間
        lastActiveTime[user] = block.timestamp;
        
        emit KarmaUpdated(user, points, newTotal);
    }

    // ==========================================
    // Progressive Social Recovery (Security Enhanced V3)
    // ==========================================

    function requestGuardianChange(address guardianA, address guardianB) external whenNotPaused {
        require(guardianA != msg.sender && guardianB != msg.sender, "Recovery: Cannot be your own guardian");
        require(guardianA != guardianB, "Recovery: Guardians must be different");
        require(guardianA != address(0) && guardianB != address(0), "Recovery: Invalid guardian address");

        // 🔴 動態時間鎖：更換守護者也必須遵守自訂延遲與心跳防護
        uint256 baseDelay = getRecoveryDelay(msg.sender);
        uint256 requiredDelay = baseDelay;

        if (isRecentlyActive(msg.sender) && ACTIVE_ACCOUNT_EXTENDED_DELAY > baseDelay) {
            requiredDelay = ACTIVE_ACCOUNT_EXTENDED_DELAY;
        }

        uint256 effectiveTime = block.timestamp + requiredDelay;
        pendingGuardianChanges[msg.sender] = PendingGuardianChange(GuardianSet(guardianA, guardianB), effectiveTime);

        emit GuardianChangeRequested(msg.sender, guardianA, guardianB, effectiveTime);
    }

    function executeGuardianChange() external whenNotPaused {
        PendingGuardianChange memory pending = pendingGuardianChanges[msg.sender];
        require(pending.effectiveTime != 0, "Recovery: No pending guardian change");
        require(block.timestamp >= pending.effectiveTime, "Recovery: Time-lock not expired yet");
        
        customGuardians[msg.sender] = pending.newGuardians;
        delete pendingGuardianChanges[msg.sender];
        
        emit GuardiansSet(msg.sender, pending.newGuardians.guardianA, pending.newGuardians.guardianB);
    }

    function adminRecoverWallet(address oldWallet, address newWallet, uint256 tokenId) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(customGuardians[oldWallet].guardianA == address(0), "Recovery: User has custom guardians, Admin locked out");
        _processRecovery(oldWallet, newWallet, tokenId, address(0), address(0));
        emit RecoveryExecuted(oldWallet, newWallet, tokenId);
    }

    function initiateRecovery(address oldWallet, address newWallet, uint256 tokenId) external whenNotPaused {
        require(balanceOf(oldWallet, tokenId) > 0, "Recovery: Old wallet has no such token");
        require(pendingRecoveries[oldWallet][tokenId].firstApprover == address(0), "Recovery: A recovery is already pending");

        GuardianSet memory guards = customGuardians[oldWallet];
        require(msg.sender == guards.guardianA || msg.sender == guards.guardianB, "Recovery: Not a designated guardian");
        require(balanceOf(msg.sender, tokenId) > 0, "Recovery: Guardian must hold an SBT");

        pendingRecoveries[oldWallet][tokenId] = RecoveryRequest(newWallet, msg.sender, block.timestamp);
        emit RecoveryInitiated(oldWallet, newWallet, tokenId, msg.sender);
    }

    // 🔴 取消救援改由「守護者」執行，防止被盜私鑰惡意干擾救援
    function cancelRecovery(address oldWallet, uint256 tokenId) external whenNotPaused {
        GuardianSet memory guards = customGuardians[oldWallet];
        require(msg.sender == guards.guardianA || msg.sender == guards.guardianB, "Recovery: Only guardians can cancel");
        require(pendingRecoveries[oldWallet][tokenId].firstApprover != address(0), "Recovery: No pending recovery");
        
        delete pendingRecoveries[oldWallet][tokenId];
        emit RecoveryCancelled(oldWallet, tokenId);
    }

    function executeRecovery(address oldWallet, address newWallet, uint256 tokenId) external whenNotPaused {
        GuardianSet memory guards = customGuardians[oldWallet];
        require(msg.sender == guards.guardianA || msg.sender == guards.guardianB, "Recovery: Not a designated guardian");
        require(balanceOf(msg.sender, tokenId) > 0, "Recovery: Guardian must hold an SBT");

        RecoveryRequest memory req = pendingRecoveries[oldWallet][tokenId];
        require(req.firstApprover != address(0), "Recovery: No recovery initiated yet");
        require(req.targetWallet == newWallet, "Recovery: Target wallet mismatch");
        require(req.firstApprover != msg.sender, "Recovery: You cannot approve twice");
        
        // 🔴 修補核心漏網之魚：將執行救援的延遲改為「動態計算（自訂延遲與心跳取大值）」
        uint256 baseDelay = getRecoveryDelay(oldWallet);
        uint256 requiredDelay = baseDelay;

        if (isRecentlyActive(oldWallet) && ACTIVE_ACCOUNT_EXTENDED_DELAY > baseDelay) {
            requiredDelay = ACTIVE_ACCOUNT_EXTENDED_DELAY;
        }

        require(block.timestamp >= req.initiatedAt + requiredDelay, "Recovery: Execution time-lock not expired");

        delete pendingRecoveries[oldWallet][tokenId];
        _processRecovery(oldWallet, newWallet, tokenId, guards.guardianA, guards.guardianB);
        emit RecoveryExecuted(oldWallet, newWallet, tokenId);
    }

    function _processRecovery(address oldWallet, address newWallet, uint256 tokenId, address guardA, address guardB) internal {
        require(balanceOf(newWallet, tokenId) == 0, "Recovery: Target wallet already holds this SBT");
        require(block.timestamp >= lastRecoveryTime[oldWallet] + 180 days, "Recovery: Cannot be recovered again within 6 months");

        uint256 balance = balanceOf(oldWallet, tokenId);
        require(balance > 0, "Recovery: No tokens to recover");
        
        _burn(oldWallet, tokenId, balance);
        _mint(newWallet, tokenId, balance, "");

        int256 oldKarma = karmaPoints[oldWallet];
        if (oldKarma != 0) {
            if (guardA != address(0) && guardB != address(0)) {
                int256 split = oldKarma / 3;
                karmaPoints[newWallet] += split;
                karmaPoints[guardA] += split;
                karmaPoints[guardB] += (oldKarma - split - split); 
            } else {
                karmaPoints[newWallet] += oldKarma / 3;
            }
        }
        karmaPoints[oldWallet] = 0; 

        lastRecoveryTime[newWallet] = block.timestamp;
        lastRecoveryTime[oldWallet] = block.timestamp;
    }

    // ==========================================
    // Soulbound Lock Mechanism
    // ==========================================
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155PausableUpgradeable, ERC1155SupplyUpgradeable)
    {
        if (from != address(0) && to != address(0)) {
            require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "PIF12: Transfers are locked. Tokens are Soulbound.");
        }
        super._update(from, to, ids, values);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ==========================================
    // Storage Gap for Upgradability
    // ==========================================
    uint256[50] private __gap;
}
