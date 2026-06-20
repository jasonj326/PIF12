// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PIF12Nexus} from "../contracts/PIF12Nexus.sol";

/// @notice Deploys PIF12Nexus v1.0.0 behind a UUPS ERC1967 proxy.
///
/// Y1 (lightweight) config:
///   - admin   = founder single EOA  (NOT a Safe; multisig migration planned Y3)
///   - gameOp  = relayer wallet       (GAME_ROLE; mint-only)
///   - forwarder = address(0)         (Y1 has no meta-tx; gasless = backend relay)
///   - issuanceEnabled deploys FALSE  (Stars/pSBT gated off until Y2)
///
/// Run (Sepolia rehearsal):
///   export ADMIN_ADDR=0x...          # founder EOA
///   export GAME_OPERATOR_ADDR=0x...  # relayer wallet (cast wallet new)
///   export BASE_URI="ipfs://CID/{id}.json"
///   forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC \
///     --private-key $DEPLOYER_KEY --broadcast --verify
///
/// The deployer (DEPLOYER_KEY) only PAYS gas; it gets no role. Admin power goes to
/// ADMIN_ADDR via initialize(). Deployer and admin may be the same EOA, or not.
contract Deploy is Script {
    function run() external returns (address proxyAddr) {
        address admin = vm.envAddress("ADMIN_ADDR");
        address gameOperator = vm.envAddress("GAME_OPERATOR_ADDR");
        address forwarder = vm.envOr("FORWARDER_ADDR", address(0));
        string memory baseURI = vm.envString("BASE_URI");

        require(admin != address(0), "ADMIN_ADDR unset");
        require(gameOperator != address(0), "GAME_OPERATOR_ADDR unset");

        bytes memory initData =
            abi.encodeCall(PIF12Nexus.initialize, (admin, gameOperator, forwarder, baseURI));

        vm.startBroadcast();
        PIF12Nexus impl = new PIF12Nexus();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        vm.stopBroadcast();

        proxyAddr = address(proxy);
        PIF12Nexus nexus = PIF12Nexus(proxyAddr);

        console.log("== PIF12Nexus deployed ==");
        console.log("implementation :", address(impl));
        console.log("proxy (USE THIS):", proxyAddr);
        console.log("version        :", nexus.VERSION());
        console.log("issuanceEnabled:", nexus.issuanceEnabled()); // must be false
        console.log("");
        console.log("Next (admin EOA, see docs/PIF12_Deploy_Checklist.md):");
        console.log("  1. setYearWindow(1, start, deadline)  -- open Horse-year minting");
        console.log("  2. verify roles + issuanceEnabled=false");
        console.log("  3. dry-run mint to a throwaway address");
    }
}
