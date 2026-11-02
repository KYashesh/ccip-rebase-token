// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console, Test} from "forge-std/Test.sol";

import {CCIPLocalSimulatorFork, Register} from "../lib/chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {
    RegistryModuleOwnerCustom
} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/contracts/libraries/RateLimiter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract CrossChainTest is Test {
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;

    uint256 public SEND_VALUE = 1e5;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    RebaseToken destRebaseToken;
    RebaseToken sourceRebaseToken;

    RebaseTokenPool destPool;
    RebaseTokenPool sourcePool;

    TokenAdminRegistry tokenAdminRegistrySepolia;
    TokenAdminRegistry tokenAdminRegistryarbSepolia;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    RegistryModuleOwnerCustom registryModuleOwnerCustomSepolia;
    RegistryModuleOwnerCustom registryModuleOwnerCustomarbSepolia;

    Vault vault;

    function setUp() public {
        // 1. Setup the Sepolia and Arbitrum Sepolia forks.
        sepoliaFork = vm.createSelectFork("sepolia-eth");
        arbSepoliaFork = vm.createFork("arb-sepolia");

        // Deploy the CCIP local fork simulator.
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 2. Deploy and configure on the source chain: Sepolia.
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        sourceRebaseToken = new RebaseToken();
        console.log("Source rebase token address:");
        console.log(address(sourceRebaseToken));
        console.log("Deploying token pool on Sepolia");

        sourcePool = new RebaseTokenPool(
            IERC20(address(sourceRebaseToken)),
            address(0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        // Deploy the vault.
        vault = new Vault(IRebaseToken(address(sourceRebaseToken)));

        // Add rewards to the vault.
        vm.deal(address(vault), 1e18);

        // Grant mint and burn permissions.
        sourceRebaseToken.grantMintAndBurnRole(address(sourcePool));
        sourceRebaseToken.grantMintAndBurnRole(address(vault));

        // Register the token administrator on Sepolia.
        registryModuleOwnerCustomSepolia = RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomSepolia.registerAdminViaOwner(address(sourceRebaseToken));

        // Accept the administrator role.
        tokenAdminRegistrySepolia = TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistrySepolia.acceptAdminRole(address(sourceRebaseToken));

        // Link the token to its pool.
        tokenAdminRegistrySepolia.setPool(address(sourceRebaseToken), address(sourcePool));
        vm.stopPrank();

        // 3. Deploy and configure on the destination chain: Arbitrum Sepolia.
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        console.log("Deploying token on Arbitrum Sepolia");
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        destRebaseToken = new RebaseToken();
        console.log("Destination rebase token address:");
        console.log(address(destRebaseToken));
        console.log("Deploying token pool on Arbitrum Sepolia");

        destPool = new RebaseTokenPool(
            IERC20(address(destRebaseToken)),
            address(0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        // Grant mint and burn permissions.
        destRebaseToken.grantMintAndBurnRole(address(destPool));

        // Register the token administrator on Arbitrum Sepolia.
        registryModuleOwnerCustomarbSepolia = RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomarbSepolia.registerAdminViaOwner(address(destRebaseToken));

        // Accept the administrator role.
        tokenAdminRegistryarbSepolia = TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistryarbSepolia.acceptAdminRole(address(destRebaseToken));

        // Link the token to its pool.
        tokenAdminRegistryarbSepolia.setPool(address(destRebaseToken), address(destPool));
        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 fork,
        TokenPool localPool,
        TokenPool remotePool,
        IRebaseToken remoteToken,
        Register.NetworkDetails memory remoteNetworkDetails
    ) public {
        vm.selectFork(fork);
        vm.startPrank(owner);

        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(address(remotePool));
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(address(remoteToken)),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            })
        });

        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        localPool.applyChainUpdates(remoteChainSelectorsToRemove, chains);
        vm.stopPrank();
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        // 1. Create the message on the source chain.
        vm.selectFork(localFork);
        vm.startPrank(user);

        Client.EVMTokenAmount[] memory tokenToSendDetails =
            new Client.EVMTokenAmount[](1);

        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({
                token: address(localToken),
                amount: amountToBridge
            });

        tokenToSendDetails[0] = tokenAmount;

        // Approve the router to burn tokens on the user's behalf.
        IERC20(address(localToken)).approve(
            localNetworkDetails.routerAddress,
            amountToBridge
        );

        Client.EVM2AnyMessage memory message =
            Client.EVM2AnyMessage({
                receiver: abi.encode(user),
                data: "",
                tokenAmounts: tokenToSendDetails,
                feeToken: localNetworkDetails.linkAddress,
                extraArgs: ""
            });
        vm.stopPrank();

        // 2. Get LINK tokens for the CCIP fee.
        uint256 fee = IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

        // 3. Approve the LINK fee and send the CCIP message.
        vm.startPrank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);
        uint256 balanceBeforeBridge = IERC20(address(localToken)).balanceOf(user);
        console.log("Local balance before bridge: %d", balanceBeforeBridge);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        uint256 sourceBalanceAfterBridge = IERC20(address(localToken)).balanceOf(user);
        console.log("Local balance after bridge: %d", sourceBalanceAfterBridge);
        assertEq(sourceBalanceAfterBridge, balanceBeforeBridge - amountToBridge);
        vm.stopPrank();

        // 4. Simulate the bridge delay on the destination chain.
        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 900);
        uint256 initialRemoteBalance = IERC20(address(remoteToken)).balanceOf(user);
        console.log("Remote balance before bridge: %d", initialRemoteBalance);

        // 5. Route the message using the CCIP local simulator.
        // Local v0.3.1 expects the source fork to be active here.
        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        console.log("Remote user interest rate: %d", remoteToken.getUserInterestRate(user));
        uint256 destinationBalance = IERC20(address(remoteToken)).balanceOf(user);
        console.log("Remote balance after bridge: %d", destinationBalance);
        assertEq(destinationBalance, initialRemoteBalance + amountToBridge);
    }

    // Bridge all tokens from Sepolia to Arbitrum Sepolia.
    function testBridgeAllTokens() public {
        configureTokenPool(
            sepoliaFork,
            sourcePool,
            destPool,
            IRebaseToken(address(destRebaseToken)),
            arbSepoliaNetworkDetails
        );

        configureTokenPool(
            arbSepoliaFork,
            destPool,
            sourcePool,
            IRebaseToken(address(sourceRebaseToken)),
            sepoliaNetworkDetails
        );

        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.startPrank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        console.log("Bridging %d tokens", SEND_VALUE);
        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(user);
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();

        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );
    }

    // Bridge all tokens to Arbitrum Sepolia and then back to Sepolia.
    function testBridgeAllTokensBack() public {
        configureTokenPool(
            sepoliaFork,
            sourcePool,
            destPool,
            IRebaseToken(address(destRebaseToken)),
            arbSepoliaNetworkDetails
        );

        configureTokenPool(
            arbSepoliaFork,
            destPool,
            sourcePool,
            IRebaseToken(address(sourceRebaseToken)),
            sepoliaNetworkDetails
        );
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.startPrank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        console.log("Bridging %d tokens", SEND_VALUE);
        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(user);
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();

        // Bridge all tokens to Arbitrum Sepolia.
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );

        // Wait one hour for interest to accrue.
        vm.selectFork(arbSepoliaFork);
        console.log("User balance before warp: %d", destRebaseToken.balanceOf(user));
        vm.warp(block.timestamp + 3600);
        console.log("User balance after warp: %d", destRebaseToken.balanceOf(user));
        uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(user);
        console.log("Amount bridging back: %d", destBalance);

        // Bridge all tokens back to Sepolia.
        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            destRebaseToken,
            sourceRebaseToken
        );
    }

    // Bridge tokens twice and then bridge them back.
    function testBridgeTwice() public {
        configureTokenPool(
            sepoliaFork,
            sourcePool,
            destPool,
            IRebaseToken(address(destRebaseToken)),
            arbSepoliaNetworkDetails
        );

        configureTokenPool(
            arbSepoliaFork,
            destPool,
            sourcePool,
            IRebaseToken(address(sourceRebaseToken)),
            sepoliaNetworkDetails
        );

        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.startPrank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(user);
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();

        // First bridge: half the tokens.
        console.log("Bridging %d tokens (first bridge)", SEND_VALUE / 2);
        bridgeTokens(
            SEND_VALUE / 2,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );

        // Wait one hour for interest to accrue on the source chain.
        vm.selectFork(sepoliaFork);
        vm.warp(block.timestamp + 3600);
        uint256 newSourceBalance = IERC20(address(sourceRebaseToken)).balanceOf(user);

        // Second bridge: remaining source tokens.
        console.log("Bridging %d tokens (second bridge)", newSourceBalance);
        bridgeTokens(
            newSourceBalance,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );

        // Wait one hour for interest to accrue on the destination chain.
        vm.selectFork(arbSepoliaFork);
        console.log("User balance before warp: %d",destRebaseToken.balanceOf(user));
        vm.warp(block.timestamp + 3600);
        console.log("User balance after warp: %d", destRebaseToken.balanceOf(user));
        uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(user);
        console.log("Amount bridging back: %d", destBalance);

        // Bridge all destination tokens back to Sepolia.
        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            destRebaseToken,
            sourceRebaseToken
        );
    }
}