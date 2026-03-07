// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/core/BasketManager.sol";
import "../src/core/RepoServicer.sol";
import "../src/core/RepoToken.sol";
import "../src/core/RepoMarket.sol";
import "../src/mocks/MockToken.sol";
import "../src/mocks/MockPriceFeed.sol";

contract DeployLocal is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // ── Deploy Mocks ──
        MockToken usdc = new MockToken("USD Coin", "USDC", 6);
        MockToken tsla = new MockToken("Tesla", "TSLA", 18);
        MockToken amzn = new MockToken("Amazon", "AMZN", 18);
        MockToken amd  = new MockToken("AMD", "AMD", 18);
        MockToken nflx = new MockToken("Netflix", "NFLX", 18);
        MockToken pltr = new MockToken("Palantir", "PLTR", 18);

        MockPriceFeed priceFeed = new MockPriceFeed();

        // Set prices (8 decimals)
        priceFeed.setPrice(address(tsla), 267_00000000);
        priceFeed.setPrice(address(amzn), 2090_00000000);
        priceFeed.setPrice(address(amd),  115_00000000);
        priceFeed.setPrice(address(nflx), 980_00000000);
        priceFeed.setPrice(address(pltr), 96_00000000);

        // Set volatilities (basis points)
        priceFeed.setVolatility(address(tsla), 2000); // 20%
        priceFeed.setVolatility(address(amzn), 1200); // 12%
        priceFeed.setVolatility(address(amd),  1800); // 18%
        priceFeed.setVolatility(address(nflx), 1500); // 15%
        priceFeed.setVolatility(address(pltr), 2200); // 22%

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

        // Mint tokens to deployer for testing
        usdc.mint(deployer, 10_000_000 * 1e6);
        tsla.mint(deployer, 200 * 1e18);
        amzn.mint(deployer, 150 * 1e18);
        amd.mint(deployer,  500 * 1e18);
        nflx.mint(deployer, 80 * 1e18);
        pltr.mint(deployer, 1500 * 1e18);

        vm.stopBroadcast();

        // Log addresses
        console.log("=== LOCAL DEPLOYMENT ===");
        console.log("USDC:", address(usdc));
        console.log("TSLA:", address(tsla));
        console.log("AMZN:", address(amzn));
        console.log("AMD:",  address(amd));
        console.log("NFLX:", address(nflx));
        console.log("PLTR:", address(pltr));
        console.log("PriceFeed:", address(priceFeed));
        console.log("BasketManager:", address(basketManager));
        console.log("RepoToken:", address(repoToken));
        console.log("RepoMarket:", address(repoMarket));
        console.log("RepoServicer:", address(servicer));
    }
}
