// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library RepoTypes {
    enum RepoState {
        Proposed,
        Active,
        MarginCalled,
        Matured,
        Settled,
        Liquidated
    }

    enum CollateralType {
        Basket,
        RepoToken
    }

    struct Basket {
        address[] tokens;
        uint256[] amounts;
        address creator;
        uint256 timestamp;
    }

    struct Repo {
        address borrower;
        address lender;
        uint256 basketId;
        uint256 principal;          // USDC amount (6 decimals)
        uint256 repoRate;           // annual rate in basis points (480 = 4.80%)
        uint256 startDate;
        uint256 maturityDate;
        RepoState state;
        uint256 mfgPaymentCredit;   // accumulated dividend credits (6 decimals)
        uint256 marginCallDeadline; // grace period end timestamp
        uint256 repoTokenId;        // minted RT id
        uint256 rehypoRepoId;       // linked downstream repo (0 if none)
        bool isRehypo;
        CollateralType collateralType;
        uint256 parentTokenId;      // if rehypo, the RT used as collateral
    }

    struct RepoTokenInfo {
        uint256 repoId;
        uint256 principal;
        uint256 repoRate;
        uint256 maturityDate;
        uint256 basketId;
        CollateralType collateralType;
        uint256 parentTokenId;
        bool isActive;
    }

    struct LenderProfile {
        uint256 minRate;         // basis points
        uint256 maxMaturity;     // seconds
        uint256 completedRepos;
        uint256 totalVolume;
        bool isRegistered;
    }
}

// ── Events ──

event BasketCreated(uint256 indexed basketId, address indexed creator, address[] tokens, uint256[] amounts);
event BasketToppedUp(uint256 indexed basketId, address indexed token, uint256 amount);

event RepoProposed(uint256 indexed repoId, address indexed borrower, address indexed lender, uint256 principal);
event RepoAccepted(uint256 indexed repoId, uint256 tokenId);
event TitleTransferred(uint256 indexed repoId, address indexed from, address indexed to);
event DividendDistributed(uint256 indexed repoId, address indexed token, uint256 totalCredit);
event MarginCallTriggered(uint256 indexed repoId, uint256 marginHealth, uint256 deadline);
event MarginRestored(uint256 indexed repoId, uint256 marginHealth);
event CollateralToppedUp(uint256 indexed repoId, address indexed token, uint256 amount);
event CollateralSubstituted(uint256 indexed repoId, address tokenOut, address tokenIn);
event RepoMatured(uint256 indexed repoId);
event RepoSettled(uint256 indexed repoId, uint256 netPayment);
event RepoLiquidated(uint256 indexed repoId);

event RehypoProposed(uint256 indexed repoId, uint256 indexed parentRepoId, uint256 repoTokenId);
event RehypoAccepted(uint256 indexed repoId, uint256 newTokenId);
event CascadeMarginCall(uint256 indexed triggeredRepoId, uint256 indexed burnedTokenId);

event LenderRegistered(address indexed lender, uint256 minRate, uint256 maxMaturity);
event ProposalListed(uint256 indexed repoId);

// ── Errors ──

error NotBorrower();
error NotLender();
error InvalidState(RepoTypes.RepoState expected, RepoTypes.RepoState actual);
error InsufficientBalance();
error BasketNotOwned();
error TokenNotInBasket();
error HaircutExceeded();
error RehypoCapExceeded();
error GraceNotExpired();
error MaturityNotReached();
error AlreadyMatured();
error InvalidBasket();
error LenderNotRegistered();
