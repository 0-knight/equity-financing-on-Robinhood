// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/core/BasketManager.sol";
import "../src/core/RepoServicer.sol";
import "../src/core/RepoToken.sol";
import "../src/core/RepoMarket.sol";
import "../src/mocks/MockToken.sol";
import "../src/mocks/MockPriceFeed.sol";
import "./Config.sol";

contract DeployRobinhood is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        NetworkConfig.Config memory cfg = NetworkConfig.getRobinhoodTestnet();

        vm.startBroadcast(deployerKey);

        // ── Deploy only what's needed ──
        // Stock tokens already exist on RH testnet — we use their addresses
        // We still need: USDC (mock), PriceFeed, and all core contracts

        MockToken usdc = new MockToken("USD Coin", "USDC", 6);
        MockPriceFeed priceFeed = new MockPriceFeed();

        // Set prices for RH testnet tokens (8 decimals)
        priceFeed.setPrice(cfg.tsla, 405_00000000);
        priceFeed.setPrice(cfg.amzn, 205_00000000);
        priceFeed.setPrice(cfg.amd,  102_00000000);
        priceFeed.setPrice(cfg.nflx, 990_00000000);
        priceFeed.setPrice(cfg.pltr, 157_00000000);

        // Set volatilities (basis points)
        priceFeed.setVolatility(cfg.tsla, 2000);
        priceFeed.setVolatility(cfg.amzn, 1200);
        priceFeed.setVolatility(cfg.amd,  1800);
        priceFeed.setVolatility(cfg.nflx, 1500);
        priceFeed.setVolatility(cfg.pltr, 2200);

        // ── Deploy Core ──
        BasketManager basketManager = new BasketManager(address(priceFeed));
        RepoToken repoToken = new RepoToken();
        RepoMarket repoMarket = new RepoMarket();
        RepoServicer servicer = new RepoServicer(
            address(basketManager),
            address(repoToken),
            address(repoMarket),
            address(usdc)
        );

        // Wire up
        repoToken.setServicer(address(servicer));

        // Mint USDC to deployer (for demo — lender needs cash)
        usdc.mint(deployer, 10_000_000 * 1e6);

        vm.stopBroadcast();

        // Log all addresses for frontend config
        console.log("=== ROBINHOOD TESTNET DEPLOYMENT ===");
        console.log("");
        console.log("--- Existing RH Tokens ---");
        console.log("WETH:", cfg.weth);
        console.log("TSLA:", cfg.tsla);
        console.log("AMZN:", cfg.amzn);
        console.log("AMD:",  cfg.amd);
        console.log("NFLX:", cfg.nflx);
        console.log("PLTR:", cfg.pltr);
        console.log("");
        console.log("--- Deployed by us ---");
        console.log("USDC:", address(usdc));
        console.log("PriceFeed:", address(priceFeed));
        console.log("BasketManager:", address(basketManager));
        console.log("RepoToken:", address(repoToken));
        console.log("RepoMarket:", address(repoMarket));
        console.log("RepoServicer:", address(servicer));
    }
}
