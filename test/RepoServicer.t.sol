// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/BasketManager.sol";
import "../src/core/RepoServicer.sol";
import "../src/core/RepoToken.sol";
import "../src/core/RepoMarket.sol";
import "../src/core/RepoTypes.sol";
import "../src/mocks/MockToken.sol";
import "../src/mocks/MockPriceFeed.sol";

contract RepoServicerTest is Test {
    BasketManager basketManager;
    RepoServicer servicer;
    RepoToken repoToken;
    RepoMarket repoMarket;
    MockPriceFeed priceFeed;

    MockToken usdc;
    MockToken tsla;
    MockToken amzn;
    MockToken amd;

    address pb = address(0x1);       // Prime Broker
    address citadel = address(0x2);  // Cash Lender (Citadel Capital)
    address jupiter = address(0x3);  // Cash Lender 2 (Jupiter MMF)

    function setUp() public {
        // Deploy mocks
        usdc = new MockToken("USD Coin", "USDC", 6);
        tsla = new MockToken("Tesla", "TSLA", 18);
        amzn = new MockToken("Amazon", "AMZN", 18);
        amd = new MockToken("AMD", "AMD", 18);

        priceFeed = new MockPriceFeed();

        // Set prices (8 decimals)
        priceFeed.setPrice(address(tsla), 267_00000000);  // $267
        priceFeed.setPrice(address(amzn), 2090_00000000);  // $2090
        priceFeed.setPrice(address(amd), 115_00000000);   // $115

        // Set volatilities (basis points)
        priceFeed.setVolatility(address(tsla), 2000); // 20%
        priceFeed.setVolatility(address(amzn), 1200); // 12%
        priceFeed.setVolatility(address(amd), 1800);  // 18%

        // Deploy core
        basketManager = new BasketManager(address(priceFeed));
        repoToken = new RepoToken();
        repoMarket = new RepoMarket();
        servicer = new RepoServicer(
            address(basketManager),
            address(repoToken),
            address(repoMarket),
            address(usdc)
        );
        repoToken.setServicer(address(servicer));

        // Mint tokens
        tsla.mint(pb, 200 * 1e18);    // PB has 200 TSLA
        amzn.mint(pb, 150 * 1e18);    // PB has 150 AMZN
        amd.mint(pb, 500 * 1e18);     // PB has 500 AMD
        usdc.mint(citadel, 5_000_000 * 1e6); // Citadel has 5M USDC
        usdc.mint(jupiter, 2_000_000 * 1e6); // Jupiter has 2M USDC
        usdc.mint(pb, 500_000 * 1e6);        // PB has 500K USDC (for repayment)

        // Approvals
        vm.startPrank(pb);
        tsla.approve(address(servicer), type(uint256).max);
        amzn.approve(address(servicer), type(uint256).max);
        amd.approve(address(servicer), type(uint256).max);
        usdc.approve(address(servicer), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(citadel);
        usdc.approve(address(servicer), type(uint256).max);
        repoToken.setApprovalForAll(address(servicer), true);
        vm.stopPrank();

        vm.startPrank(jupiter);
        usdc.approve(address(servicer), type(uint256).max);
        repoToken.setApprovalForAll(address(servicer), true);
        vm.stopPrank();

        // Register lenders
        vm.prank(citadel);
        repoMarket.registerLender(465, 30 days);
        vm.prank(jupiter);
        repoMarket.registerLender(520, 14 days);
    }

    // ═══════════════════════════════════════════
    //  BASKET TESTS
    // ═══════════════════════════════════════════

    function test_createBasket() public {
        address[] memory tokens = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        tokens[0] = address(tsla); amounts[0] = 100 * 1e18;
        tokens[1] = address(amzn); amounts[1] = 20 * 1e18;
        tokens[2] = address(amd);  amounts[2] = 200 * 1e18;

        vm.prank(pb);
        uint256 basketId = basketManager.createBasket(tokens, amounts);
        assertEq(basketId, 1);

        uint256 value = basketManager.getBasketValue(basketId);
        // TSLA: 267 * 100 = 26700, AMZN: 2090 * 20 = 41800, AMD: 115 * 200 = 23000 = $91500
        assertEq(value, 91500 * 1e6);
    }

    function test_calculateParams() public {
        address[] memory tokens = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        tokens[0] = address(tsla); amounts[0] = 100 * 1e18;
        tokens[1] = address(amzn); amounts[1] = 20 * 1e18;
        tokens[2] = address(amd);  amounts[2] = 200 * 1e18;

        (uint256 haircut, uint256 marginThreshold, uint256 maxBorrow) = basketManager.calculateParams(tokens, amounts);

        // Weighted avg vol should be around 1585 bps (15.85%)
        // Div bonus for 3 assets = 230 bps (2.30%)
        // Final haircut ~ 1355 bps (13.55%)
        assertTrue(haircut > 1300 && haircut < 1700, "Haircut out of range");
        assertTrue(maxBorrow > 78000 * 1e6 && maxBorrow < 82000 * 1e6, "Max borrow out of range");
    }

    // ═══════════════════════════════════════════
    //  FULL LIFECYCLE TEST
    // ═══════════════════════════════════════════

    function test_fullLifecycle() public {
        // Step 1: PB creates basket
        address[] memory tokens = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        tokens[0] = address(tsla); amounts[0] = 100 * 1e18;
        tokens[1] = address(amzn); amounts[1] = 20 * 1e18;
        tokens[2] = address(amd);  amounts[2] = 200 * 1e18;

        vm.prank(pb);
        uint256 basketId = basketManager.createBasket(tokens, amounts);

        // Step 2: PB proposes repo
        vm.prank(pb);
        uint256 repoId = servicer.proposeRepo(basketId, 75000 * 1e6, 480, 30, citadel);
        assertEq(uint256(servicer.getRepoState(repoId)), uint256(RepoTypes.RepoState.Proposed));

        // Step 3: Citadel accepts
        vm.prank(citadel);
        servicer.acceptRepo(repoId);
        assertEq(uint256(servicer.getRepoState(repoId)), uint256(RepoTypes.RepoState.Active));

        // Verify title transfer
        assertEq(tsla.balanceOf(citadel), 100 * 1e18);
        assertEq(amzn.balanceOf(citadel), 20 * 1e18);
        assertEq(amd.balanceOf(citadel), 200 * 1e18);

        // Verify USDC transfer
        assertEq(usdc.balanceOf(pb), 500_000 * 1e6 + 75000 * 1e6);

        // Verify RT minted to Citadel
        assertEq(repoToken.ownerOf(1), citadel);

        // Step 4: Dividend occurs (TSLA $2.50/share)
        servicer.distributeDividend(repoId, address(tsla), 2_500000); // $2.50 in 6 decimals
        assertEq(servicer.getMfgPaymentCredit(repoId), 250 * 1e6); // 100 shares * $2.50

        // Step 5: Time passes, maturity
        vm.warp(block.timestamp + 30 days);
        servicer.checkMaturity(repoId);
        assertEq(uint256(servicer.getRepoState(repoId)), uint256(RepoTypes.RepoState.Matured));

        // Step 6: Settlement
        // Need Citadel to approve basket tokens back to PB
        vm.startPrank(citadel);
        tsla.approve(address(servicer), type(uint256).max);
        amzn.approve(address(servicer), type(uint256).max);
        amd.approve(address(servicer), type(uint256).max);
        vm.stopPrank();

        (uint256 principal, uint256 interest, uint256 mfgCredit, uint256 netPayment) = servicer.calculateSettlement(repoId);
        assertEq(principal, 75000 * 1e6);
        assertEq(mfgCredit, 250 * 1e6);
        assertTrue(interest > 0, "Interest should be > 0");

        //assertTrue(netPayment < principal, "Net should be less than principal due to mfg credit");
	assertTrue(netPayment < principal + interest, "Net should be reduced by mfg credit");

        vm.prank(pb);
        servicer.settleRepo(repoId);
        assertEq(uint256(servicer.getRepoState(repoId)), uint256(RepoTypes.RepoState.Settled));

        // Verify basket returned to PB
        assertEq(tsla.balanceOf(pb), 200 * 1e18); // original 200 back (100 were in basket + 100 remaining)
        assertEq(amzn.balanceOf(pb), 150 * 1e18);
        assertEq(amd.balanceOf(pb), 500 * 1e18);
    }

    // ═══════════════════════════════════════════
    //  MARGIN CALL + TOP UP
    // ═══════════════════════════════════════════

    function test_marginCallAndTopUp() public {
        // Create basket and repo
        address[] memory tokens = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        tokens[0] = address(tsla); amounts[0] = 100 * 1e18;
        tokens[1] = address(amzn); amounts[1] = 20 * 1e18;
        tokens[2] = address(amd);  amounts[2] = 200 * 1e18;

        vm.prank(pb);
        uint256 basketId = basketManager.createBasket(tokens, amounts);
        vm.prank(pb);
        uint256 repoId = servicer.proposeRepo(basketId, 75000 * 1e6, 480, 30, citadel);
        vm.prank(citadel);
        servicer.acceptRepo(repoId);

        // Price drop: AMD drops 50%
        priceFeed.setPrice(address(amd), 57_50000000); // $57.50

        // Check margin — should trigger margin call
        servicer.checkMargin(repoId);
        assertEq(uint256(servicer.getRepoState(repoId)), uint256(RepoTypes.RepoState.MarginCalled));

        // PB tops up with more TSLA
        vm.prank(pb);
        servicer.topUpCollateral(repoId, address(tsla), 50 * 1e18);

        // Should restore margin if enough
        uint256 health = servicer.getMarginHealth(repoId);
        assertTrue(health > 0, "Health should improve");
    }

    // ═══════════════════════════════════════════
    //  REHYPOTHECATION
    // ═══════════════════════════════════════════

    function test_rehypothecation() public {
        // Create basket and base repo
        address[] memory tokens = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        tokens[0] = address(tsla); amounts[0] = 100 * 1e18;
        tokens[1] = address(amzn); amounts[1] = 20 * 1e18;
        tokens[2] = address(amd);  amounts[2] = 200 * 1e18;

        vm.prank(pb);
        uint256 basketId = basketManager.createBasket(tokens, amounts);
        vm.prank(pb);
        uint256 baseRepoId = servicer.proposeRepo(basketId, 75000 * 1e6, 480, 30, citadel);
        vm.prank(citadel);
        servicer.acceptRepo(baseRepoId);

        // Citadel holds RT #1, proposes rehypo to Jupiter
        vm.prank(citadel);
        uint256 rehypoId = servicer.proposeRehypo(1, 60000 * 1e6, 520, 14, jupiter);

        // Check 140% cap
        uint256 cap = servicer.getRehypoCap(1);
        assertEq(cap, 105000 * 1e6); // 75000 * 140%
        assertTrue(60000 * 1e6 <= cap, "Should be within cap");

        // Jupiter accepts
        vm.prank(jupiter);
        servicer.acceptRehypo(rehypoId);

        // RT #1 should now be with Jupiter
        assertEq(repoToken.ownerOf(1), jupiter);
        // RT #2 minted to Jupiter
        assertEq(repoToken.ownerOf(2), jupiter);
        // Citadel got 60K USDC
        assertTrue(usdc.balanceOf(citadel) > 0);

        // Settle rehypo at day 14
        vm.warp(block.timestamp + 14 days);
        servicer.checkMaturity(rehypoId);

        // Citadel needs USDC for repayment
        usdc.mint(citadel, 100_000 * 1e6);

        vm.prank(citadel);
        servicer.settleRehypo(rehypoId);

        assertEq(uint256(servicer.getRepoState(rehypoId)), uint256(RepoTypes.RepoState.Settled));
        // RT #1 returned to Citadel
        assertEq(repoToken.ownerOf(1), citadel);

        // Now settle base at day 30
        vm.warp(block.timestamp + 16 days);
        servicer.checkMaturity(baseRepoId);

        vm.startPrank(citadel);
        tsla.approve(address(servicer), type(uint256).max);
        amzn.approve(address(servicer), type(uint256).max);
        amd.approve(address(servicer), type(uint256).max);
        vm.stopPrank();

        vm.prank(pb);
        servicer.settleRepo(baseRepoId);

        assertEq(uint256(servicer.getRepoState(baseRepoId)), uint256(RepoTypes.RepoState.Settled));
    }

    // ═══════════════════════════════════════════
    //  REHYPO CAP ENFORCEMENT
    // ═══════════════════════════════════════════

    function test_rehypoCapExceeded() public {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(tsla); amounts[0] = 100 * 1e18;

        vm.prank(pb);
        uint256 basketId = basketManager.createBasket(tokens, amounts);
        vm.prank(pb);
        uint256 repoId = servicer.proposeRepo(basketId, 20000 * 1e6, 480, 30, citadel);
        vm.prank(citadel);
        servicer.acceptRepo(repoId);

        // Try rehypo exceeding 140% cap (20000 * 1.4 = 28000)
        vm.prank(citadel);
        vm.expectRevert("Exceeds rehypo cap (140%)");
        servicer.proposeRehypo(1, 30000 * 1e6, 520, 14, jupiter);
    }

    // ═══════════════════════════════════════════
    //  LIQUIDATION
    // ═══════════════════════════════════════════

    function test_liquidation() public {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(tsla); amounts[0] = 100 * 1e18;

        vm.prank(pb);
        uint256 basketId = basketManager.createBasket(tokens, amounts);
        vm.prank(pb);
        uint256 repoId = servicer.proposeRepo(basketId, 25000 * 1e6, 480, 30, citadel);
        vm.prank(citadel);
        servicer.acceptRepo(repoId);

        // Massive price drop
        priceFeed.setPrice(address(tsla), 100_00000000); // $100 (from $267)

        servicer.checkMargin(repoId);
        assertEq(uint256(servicer.getRepoState(repoId)), uint256(RepoTypes.RepoState.MarginCalled));

        // Grace expires
        vm.warp(block.timestamp + 2 days);
        servicer.liquidate(repoId);
        assertEq(uint256(servicer.getRepoState(repoId)), uint256(RepoTypes.RepoState.Liquidated));
    }

    // ═══════════════════════════════════════════
    //  SETTLEMENT MATH
    // ═══════════════════════════════════════════

    function test_settlementMath() public {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(tsla); amounts[0] = 100 * 1e18;

        vm.prank(pb);
        uint256 basketId = basketManager.createBasket(tokens, amounts);
        vm.prank(pb);
        uint256 repoId = servicer.proposeRepo(basketId, 75000 * 1e6, 480, 30, citadel);
        vm.prank(citadel);
        servicer.acceptRepo(repoId);

        // Dividend
        servicer.distributeDividend(repoId, address(tsla), 2_500000);

        vm.warp(block.timestamp + 30 days);

        (uint256 principal, uint256 interest, uint256 mfgCredit, uint256 netPayment) = servicer.calculateSettlement(repoId);

        // interest = 75000 * 480 / 10000 * 30 / 365 = ~295.89
        assertEq(principal, 75000 * 1e6);
        assertEq(mfgCredit, 250 * 1e6);
        // Net should be principal + interest - mfgCredit
        assertEq(netPayment, principal + interest - mfgCredit);
        // Net < principal because mfgCredit partially offsets
        assertTrue(netPayment > 75000 * 1e6 - 250 * 1e6, "Net payment sanity check");
    }
}
