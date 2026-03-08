// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./RepoTypes.sol";
import "./BasketManager.sol";
import "./RepoToken.sol";
import "./RepoMarket.sol";

contract RepoServicer is Ownable {
    using SafeERC20 for IERC20;

    BasketManager public basketManager;
    RepoToken public repoToken;
    RepoMarket public repoMarket;
    IERC20 public usdc;

    uint256 public nextRepoId = 1;
    mapping(uint256 => RepoTypes.Repo) public repos;

    // borrower => repoIds
    mapping(address => uint256[]) public borrowerRepos;
    // lender => repoIds
    mapping(address => uint256[]) public lenderRepos;

    uint256 public constant GRACE_PERIOD = 1 days;
    uint256 public constant REHYPO_CAP_BPS = 14000; // 140% in basis points
    uint256 public constant BASIS = 10000;
    uint256 public constant YEAR = 365 days;

    constructor(
        address _basketManager,
        address _repoToken,
        address _repoMarket,
        address _usdc
    ) Ownable(msg.sender) {
        basketManager = BasketManager(_basketManager);
        repoToken = RepoToken(_repoToken);
        repoMarket = RepoMarket(_repoMarket);
        usdc = IERC20(_usdc);
    }

    // ═══════════════════════════════════════════
    //  PROPOSE
    // ═══════════════════════════════════════════

    function proposeRepo(
        uint256 basketId,
        uint256 principal,
        uint256 repoRate,
        uint256 maturityDays,
        address lender
    ) external returns (uint256 repoId) {
        (address[] memory tokens, uint256[] memory amounts, address creator) = basketManager.getBasket(basketId);
        require(creator == msg.sender, "Not basket creator");
        require(principal > 0, "Zero principal");
        require(lender != address(0), "Zero lender");

        // Verify borrower owns all basket tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            require(
                IERC20(tokens[i]).balanceOf(msg.sender) >= amounts[i],
                "Insufficient token balance"
            );
        }

        repoId = nextRepoId++;
        repos[repoId] = RepoTypes.Repo({
            borrower: msg.sender,
            lender: lender,
            basketId: basketId,
            principal: principal,
            repoRate: repoRate,
            startDate: 0,
            maturityDate: 0,
            state: RepoTypes.RepoState.Proposed,
            mfgPaymentCredit: 0,
            marginCallDeadline: 0,
            repoTokenId: 0,
            rehypoRepoId: 0,
            isRehypo: false,
            collateralType: RepoTypes.CollateralType.Basket,
            parentTokenId: 0
        });

        borrowerRepos[msg.sender].push(repoId);
        lenderRepos[lender].push(repoId);

        // List on market
        repoMarket.listProposal(repoId, lender);

        emit RepoProposed(repoId, msg.sender, lender, principal);
    }

    // ═══════════════════════════════════════════
    //  ACCEPT — Title Transfer + RT Mint
    // ═══════════════════════════════════════════

    function acceptRepo(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        require(repo.state == RepoTypes.RepoState.Proposed, "Not proposed");
        require(msg.sender == repo.lender, "Not lender");

        (address[] memory tokens, uint256[] memory amounts,) = basketManager.getBasket(repo.basketId);

        // Title transfer: basket tokens from borrower → lender
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransferFrom(repo.borrower, repo.lender, amounts[i]);
        }

        // Cash transfer: USDC from lender → borrower
        usdc.safeTransferFrom(repo.lender, repo.borrower, repo.principal);

        // Set dates
        repo.startDate = block.timestamp;
        repo.maturityDate = block.timestamp + 30 days; // simplified; could use maturityDays
        repo.state = RepoTypes.RepoState.Active;

        // Mint RepoToken to lender
        uint256 tokenId = repoToken.mint(
            repo.lender,
            repoId,
            repo.principal,
            repo.repoRate,
            repo.maturityDate,
            repo.basketId,
            RepoTypes.CollateralType.Basket,
            0
        );
        repo.repoTokenId = tokenId;

        // Remove from open proposals
        repoMarket.removeProposal(repoId);

        emit RepoAccepted(repoId, tokenId);
        emit TitleTransferred(repoId, repo.borrower, repo.lender);
    }

    // ═══════════════════════════════════════════
    //  DIVIDEND / MANUFACTURED PAYMENT
    // ═══════════════════════════════════════════

    function distributeDividend(
        uint256 repoId,
        address token,
        uint256 amountPerShare
    ) external onlyOwner {
        RepoTypes.Repo storage repo = repos[repoId];
        require(repo.state == RepoTypes.RepoState.Active || repo.state == RepoTypes.RepoState.MarginCalled, "Not active");

        (address[] memory tokens, uint256[] memory amounts,) = basketManager.getBasket(repo.basketId);

        uint256 totalCredit = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                // amountPerShare in USDC (6 decimals), amounts[i] in token decimals (18)
                // shares = amounts[i] / 1e18
                totalCredit = (amountPerShare * amounts[i]) / 1e18;
                break;
            }
        }
        require(totalCredit > 0, "Token not in basket or zero");

        repo.mfgPaymentCredit += totalCredit;

        emit DividendDistributed(repoId, token, totalCredit);
    }

    // ═══════════════════════════════════════════
    //  MARGIN CHECK + CALL
    // ═══════════════════════════════════════════

    function checkMargin(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        require(repo.state == RepoTypes.RepoState.Active, "Not active");

        uint256 health = getMarginHealth(repoId);

        if (health < 4000) { // below 40%
            repo.state = RepoTypes.RepoState.MarginCalled;
            repo.marginCallDeadline = block.timestamp + GRACE_PERIOD;
            emit MarginCallTriggered(repoId, health, repo.marginCallDeadline);
        }
    }

    function topUpCollateral(uint256 repoId, address token, uint256 amount) external {
        RepoTypes.Repo storage repo = repos[repoId];
        require(msg.sender == repo.borrower, "Not borrower");
        require(
            repo.state == RepoTypes.RepoState.MarginCalled || repo.state == RepoTypes.RepoState.Active,
            "Cannot top up"
        );

        // Transfer additional tokens from borrower → lender
        IERC20(token).safeTransferFrom(repo.borrower, repo.lender, amount);

        // Update basket
        basketManager.addToBasket(repo.basketId, token, amount);

        emit CollateralToppedUp(repoId, token, amount);

        // Recheck margin
        uint256 health = getMarginHealth(repoId);
        if (health >= 6000 && repo.state == RepoTypes.RepoState.MarginCalled) {
            repo.state = RepoTypes.RepoState.Active;
            repo.marginCallDeadline = 0;
            emit MarginRestored(repoId, health);
        }
    }

    function liquidate(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        require(repo.state == RepoTypes.RepoState.MarginCalled, "Not margin called");
        require(block.timestamp >= repo.marginCallDeadline, "Grace not expired");

        repo.state = RepoTypes.RepoState.Liquidated;

        // Lender keeps the basket (already holds it via title transfer)
        // Burn RepoToken
        if (repo.repoTokenId != 0) {
            repoToken.burn(repo.repoTokenId);
        }

        emit RepoLiquidated(repoId);
    }

    // ═══════════════════════════════════════════
    //  MATURITY + SETTLEMENT
    // ═══════════════════════════════════════════

    function checkMaturity(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        require(repo.state == RepoTypes.RepoState.Active || repo.state == RepoTypes.RepoState.MarginCalled, "Cannot mature");
        require(block.timestamp >= repo.maturityDate, "Not matured yet");

        repo.state = RepoTypes.RepoState.Matured;
        emit RepoMatured(repoId);
    }

    function settleRepo(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        require(repo.state == RepoTypes.RepoState.Matured, "Not matured");
        require(msg.sender == repo.borrower, "Not borrower");

        (uint256 principal, uint256 interest, uint256 mfgCredit, uint256 netPayment) = calculateSettlement(repoId);

        // Borrower pays net amount to lender
        usdc.safeTransferFrom(repo.borrower, repo.lender, netPayment);

        // Return basket: lender → borrower
        (address[] memory tokens, uint256[] memory amounts,) = basketManager.getBasket(repo.basketId);
        address lender = repo.lender;
        address borrower = repo.borrower;
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransferFrom(lender, borrower, amounts[i]);
        }

        // Check for cascade before burning
        uint256 tokenId = repo.repoTokenId;
        uint256 rehypoId = repoToken.rehypoOf(tokenId);

        // Burn RepoToken
        repoToken.burn(tokenId);

        // Cascade: if this RT was used as rehypo collateral
        if (rehypoId != 0) {
            RepoTypes.Repo storage downstream = repos[rehypoId];
            if (downstream.state == RepoTypes.RepoState.Active) {
                downstream.state = RepoTypes.RepoState.MarginCalled;
                downstream.marginCallDeadline = block.timestamp + GRACE_PERIOD;
                emit CascadeMarginCall(rehypoId, tokenId);
            }
        }

        repo.state = RepoTypes.RepoState.Settled;

        // Update market stats
        repoMarket.recordCompletion(repo.lender, repo.principal);

        emit RepoSettled(repoId, netPayment);
    }

    /// @notice DEBUG ONLY — force maturity for demo
    function debugSetMaturity(uint256 repoId, uint256 newMaturity) external onlyOwner {
   	 repos[repoId].maturityDate = newMaturity;
    }

    /// @notice DEBUG ONLY — force state for demo
    function debugSetState(uint256 repoId, RepoTypes.RepoState newState) external onlyOwner {
    	repos[repoId].state = newState;
    }

    /// @notice DEBUG ONLY — force start date for demo
    function debugSetStartDate(uint256 repoId, uint256 newStart) external onlyOwner {
        repos[repoId].startDate = newStart;
    }

    // ═══════════════════════════════════════════
    //  REHYPOTHECATION
    // ═══════════════════════════════════════════

    function proposeRehypo(
        uint256 repoTokenId,
        uint256 principal,
        uint256 repoRate,
        uint256 maturityDays,
        address lender
    ) external returns (uint256 repoId) {
        require(repoToken.ownerOf(repoTokenId) == msg.sender, "Not RT owner");
        require(repoToken.isRehypoAvailable(repoTokenId), "RT not available for rehypo");

        // Check 140% cap
        RepoTypes.RepoTokenInfo memory info = repoToken.getRepoTokenInfo(repoTokenId);
        uint256 cap = (info.principal * REHYPO_CAP_BPS) / BASIS;
        require(principal <= cap, "Exceeds rehypo cap (140%)");

        repoId = nextRepoId++;
        repos[repoId] = RepoTypes.Repo({
            borrower: msg.sender,
            lender: lender,
            basketId: 0, // no basket, collateral is RT
            principal: principal,
            repoRate: repoRate,
            startDate: 0,
            maturityDate: 0,
            state: RepoTypes.RepoState.Proposed,
            mfgPaymentCredit: 0,
            marginCallDeadline: 0,
            repoTokenId: 0,
            rehypoRepoId: 0,
            isRehypo: true,
            collateralType: RepoTypes.CollateralType.RepoToken,
            parentTokenId: repoTokenId
        });

        borrowerRepos[msg.sender].push(repoId);
        lenderRepos[lender].push(repoId);

        repoMarket.listProposal(repoId, lender);

        emit RehypoProposed(repoId, info.repoId, repoTokenId);
    }

    function acceptRehypo(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        require(repo.state == RepoTypes.RepoState.Proposed, "Not proposed");
        require(repo.isRehypo, "Not a rehypo");
        require(msg.sender == repo.lender, "Not lender");

        uint256 parentTokenId = repo.parentTokenId;

        // Transfer RT from borrower → new lender
        repoToken.transferFrom(repo.borrower, repo.lender, parentTokenId);

        // Mark RT as rehypo'd
        repoToken.setRehypo(parentTokenId, repoId);

        // Cash: USDC from new lender → borrower
        usdc.safeTransferFrom(repo.lender, repo.borrower, repo.principal);

        repo.startDate = block.timestamp;
        repo.maturityDate = block.timestamp + 14 days; // shorter than base
        repo.state = RepoTypes.RepoState.Active;

        // Mint new RT (#2) to new lender
        uint256 newTokenId = repoToken.mint(
            repo.lender,
            repoId,
            repo.principal,
            repo.repoRate,
            repo.maturityDate,
            0, // no basket
            RepoTypes.CollateralType.RepoToken,
            parentTokenId
        );
        repo.repoTokenId = newTokenId;

        // Link parent repo to this rehypo
        RepoTypes.RepoTokenInfo memory parentInfo = repoToken.getRepoTokenInfo(parentTokenId);
        repos[parentInfo.repoId].rehypoRepoId = repoId;

        repoMarket.removeProposal(repoId);

        emit RehypoAccepted(repoId, newTokenId);
    }

    function settleRehypo(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        require(repo.state == RepoTypes.RepoState.Matured, "Not matured");
        require(repo.isRehypo, "Not rehypo");
        require(msg.sender == repo.borrower, "Not borrower");

        (, , , uint256 netPayment) = calculateSettlement(repoId);

        // Borrower pays lender
        usdc.safeTransferFrom(repo.borrower, repo.lender, netPayment);

        // Return parent RT: lender → borrower
        uint256 parentTokenId = repo.parentTokenId;
        repoToken.transferFrom(repo.lender, repo.borrower, parentTokenId);

        // Clear rehypo link
        repoToken.clearRehypo(parentTokenId);

        // Clear parent repo's rehypo link
        RepoTypes.RepoTokenInfo memory parentInfo = repoToken.getRepoTokenInfo(parentTokenId);
        repos[parentInfo.repoId].rehypoRepoId = 0;

        // Burn RT #2
        repoToken.burn(repo.repoTokenId);

        repo.state = RepoTypes.RepoState.Settled;

        repoMarket.recordCompletion(repo.lender, repo.principal);

        emit RepoSettled(repoId, netPayment);
    }

    // ═══════════════════════════════════════════
    //  COLLATERAL SUBSTITUTION
    // ═══════════════════════════════════════════

    // Simplified: borrower proposes + lender approves in one tx (for demo)
    function substituteCollateral(
        uint256 repoId,
        address tokenOut,
        uint256 amountOut,
        address tokenIn,
        uint256 amountIn
    ) external {
        RepoTypes.Repo storage repo = repos[repoId];
        require(msg.sender == repo.lender, "Not lender"); // lender approves
        require(repo.state == RepoTypes.RepoState.Active, "Not active");

        // tokenOut: lender → borrower
        IERC20(tokenOut).safeTransferFrom(repo.lender, repo.borrower, amountOut);

        // tokenIn: borrower → lender
        IERC20(tokenIn).safeTransferFrom(repo.borrower, repo.lender, amountIn);

        // Update basket (would need basket update logic — simplified)
        emit CollateralSubstituted(repoId, tokenOut, tokenIn);
    }

    // ═══════════════════════════════════════════
    //  VIEW FUNCTIONS
    // ═══════════════════════════════════════════

    function getRepoState(uint256 repoId) external view returns (RepoTypes.RepoState) {
        return repos[repoId].state;
    }

    function getRepoTerms(uint256 repoId) external view returns (
        uint256 principal,
        uint256 repoRate,
        uint256 maturityDate,
        uint256 basketId
    ) {
        RepoTypes.Repo storage r = repos[repoId];
        return (r.principal, r.repoRate, r.maturityDate, r.basketId);
    }

    function calculateAccruedInterest(uint256 repoId) public view returns (uint256) {
        RepoTypes.Repo storage r = repos[repoId];
        if (r.startDate == 0) return 0;
        uint256 elapsed = block.timestamp - r.startDate;
        if (elapsed > r.maturityDate - r.startDate) {
            elapsed = r.maturityDate - r.startDate;
        }
        // interest = principal * rate * elapsed / (BASIS * YEAR)
        return (r.principal * r.repoRate * elapsed) / (BASIS * YEAR);
    }

    function getMfgPaymentCredit(uint256 repoId) external view returns (uint256) {
        return repos[repoId].mfgPaymentCredit;
    }

    function calculateSettlement(uint256 repoId) public view returns (
        uint256 principal,
        uint256 interest,
        uint256 mfgCredit,
        uint256 netPayment
    ) {
        RepoTypes.Repo storage r = repos[repoId];
        principal = r.principal;
        interest = calculateAccruedInterest(repoId);
        mfgCredit = r.mfgPaymentCredit;

        if (principal + interest > mfgCredit) {
            netPayment = principal + interest - mfgCredit;
        } else {
            netPayment = 0;
        }
    }

    function getMarginHealth(uint256 repoId) public view returns (uint256) {
        RepoTypes.Repo storage r = repos[repoId];
        if (r.collateralType == RepoTypes.CollateralType.RepoToken) {
            // For rehypo, use parent RT value
            RepoTypes.RepoTokenInfo memory info = repoToken.getRepoTokenInfo(r.parentTokenId);
            uint256 rtValue = info.principal; // simplified
            if (rtValue <= r.principal) return 0;
            return ((rtValue - r.principal) * BASIS) / rtValue;
        }

        uint256 basketValue = basketManager.getBasketValue(r.basketId);
        if (basketValue <= r.principal) return 0;
        // health = (basketValue - principal) / basketValue * 10000
        return ((basketValue - r.principal) * BASIS) / basketValue;
    }

    function isMarginCalled(uint256 repoId) external view returns (bool) {
        return repos[repoId].state == RepoTypes.RepoState.MarginCalled;
    }

    function getGraceDeadline(uint256 repoId) external view returns (uint256) {
        return repos[repoId].marginCallDeadline;
    }

    function getMaturityDate(uint256 repoId) external view returns (uint256) {
        return repos[repoId].maturityDate;
    }

    function getRehypoCap(uint256 repoTokenId) external view returns (uint256) {
        RepoTypes.RepoTokenInfo memory info = repoToken.getRepoTokenInfo(repoTokenId);
        return (info.principal * REHYPO_CAP_BPS) / BASIS;
    }

    function getRehypoChain(uint256 repoId) external view returns (uint256[] memory) {
        uint256[] memory chain = new uint256[](10); // max 10 deep
        uint256 current = repoId;
        uint256 depth = 0;
        while (current != 0 && depth < 10) {
            chain[depth] = current;
            current = repos[current].rehypoRepoId;
            depth++;
        }
        // Trim
        uint256[] memory result = new uint256[](depth);
        for (uint256 i = 0; i < depth; i++) {
            result[i] = chain[i];
        }
        return result;
    }

    function getReposByBorrower(address borrower) external view returns (uint256[] memory) {
        return borrowerRepos[borrower];
    }

    function getReposByLender(address lender) external view returns (uint256[] memory) {
        return lenderRepos[lender];
    }
}
