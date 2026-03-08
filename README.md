# On-Chain Equity Repo for Prime Brokers

**Equity Financing in a Smart Contract**

Live on Robinhood Chain Testnet · Built for the Robinhood × Arbitrum × LayerZero Hackathon

---

## Why This Exists

Robinhood Chain puts tokenized equities on-chain. TSLA, AMZN, AMD, NFLX, PLTR — real stock tokens, ERC-20, tradeable 24/7. But having tokenized securities on-chain is only the first step. The next question is: what can you *do* with them?

In traditional finance, the answer is clear. You finance them. A prime broker holding $100M in equities doesn't let them sit idle — they use those securities as collateral to borrow cash, fund new positions, and generate returns. This is the backbone of institutional capital markets.

On-chain today, the only option is pool-based lending: Aave, Compound, Morpho. These protocols were designed for fungible crypto tokens like ETH and WBTC. They work well for that purpose. But they fundamentally do not work for equity securities, and no institutional participant will use them. Here's why.

## The Problem with Pools for Equities

### Tax Bomb

When you deposit TSLA into a lending vault, the tax treatment is problematic. The transfer of tokens into a smart contract can be classified as a disposal — effectively a sale — triggering capital gains tax on any unrealized appreciation. For an institution managing a $100M equity portfolio, this creates an immediate and significant tax liability before a single dollar has been borrowed.

This is not a theoretical concern. It is the primary reason institutions have not adopted DeFi lending for securities. Tax counsel at every major bank and hedge fund will reject any structure that creates an unnecessary taxable event.

### Fragmented — No Portfolio Financing

Pools are designed around individual tokens. One pool for TSLA, another for AMZN, a third for AMD. Each with its own interest rate, its own collateral ratio, its own risk parameters.

But institutions don't finance stocks one at a time. They finance portfolios. A prime broker's entire book of holdings is pledged as a single collateral package. This matters because a diversified portfolio has lower risk than any individual stock — but pools have no mechanism to recognize this. A basket of TSLA, AMZN, and AMD together deserves a lower haircut than TSLA alone, because the correlation between these stocks is less than 1. Pools cannot capture this diversification benefit, which means institutions get worse terms than they should.

### Dead Capital — No Rehypothecation

In a lending pool, collateral is locked in a smart contract. The lender deposits cash into the pool and receives interest — but they never take possession of the collateral itself. The borrower's securities sit in the vault, untouched, until the position is unwound.

In traditional finance, this would be unthinkable. When a prime broker lends cash against a client's equity portfolio, the prime broker receives actual title to those securities. They can then use those securities in their own operations — lending them out, pledging them as collateral for their own borrowing, or using them for settlement. This practice is called rehypothecation, and it is the primary mechanism through which capital markets achieve liquidity and efficiency.

Pool-based lending makes rehypothecation impossible. The result is dead capital — the most liquid assets in the world, locked in a contract, generating no additional value.

## The Solution: Equity Repo

Repo — short for repurchase agreement — is the instrument that Wall Street uses to solve all three of these problems. It is not new or experimental. The U.S. repo market processes approximately $4 trillion in transactions every single day. Every major bank, every prime broker, and every hedge fund uses repo as their primary tool for equity financing.

We built an on-chain implementation of equity repo that faithfully reproduces this structure in smart contracts, deployed on Robinhood Chain testnet using all five available stock tokens.

### Tax-Neutral by Design

A repo is legally classified as a financing transaction, not a sale. Here's how it works: the borrower (a prime broker) transfers title of their securities to the lender (a cash provider), and simultaneously agrees to repurchase those same securities at a future date for the original price plus interest.

Despite the fact that title changes hands, the economic substance is a secured loan. Tax authorities — including the IRS — recognize this distinction. Because the borrower has a binding obligation to repurchase, the transaction is not treated as a disposal. No capital gains tax is triggered. The borrower's cost basis is preserved.

This is not a loophole or a gray area. It is the established, well-understood legal framework under which trillions of dollars of equity financing occurs every day. By replicating this exact structure on-chain, we make equity financing accessible to institutions in a way that pools never can.

On-chain, we implement this through actual ERC-20 title transfer — the stock tokens move from the borrower's wallet to the lender's wallet — while the smart contract encodes the repurchase obligation, maturity date, and interest rate. The legal structure maps directly to the on-chain mechanics.

### Basket Collateral — Portfolio-Level Financing

In traditional prime brokerage, a client's entire equity portfolio serves as collateral — not individual positions. Our protocol reproduces this through basket collateral.

A prime broker selects multiple securities into a single basket — for example, TSLA, AMZN, and AMD. The BasketManager contract calculates a blended haircut using each token's volatility, weighted by its proportion of the basket's total value. Critically, the contract applies a diversification bonus: each additional asset in the basket reduces the overall haircut, reflecting the lower risk of a diversified portfolio compared to a concentrated position.

**Haircut Formula:**
- Each token has a preset volatility: TSLA 20%, AMZN 12%, AMD 18%, NFLX 15%, PLTR 22%
- Weighted average = Σ (token_value / basket_value × token_volatility)
- Diversification bonus = (number_of_assets − 1) × 1.15%
- Final haircut = max(5%, weighted_average − diversification_bonus)

This means a three-asset basket might receive a 13.5% haircut instead of the 20% that TSLA alone would require — directly increasing the borrower's available financing. This is the on-chain equivalent of portfolio margining, a standard practice at every prime broker.

### Rehypothecation via Title Transfer — with On-Chain Compliance

This is where on-chain equity repo becomes truly powerful, and where it diverges most significantly from pool-based lending.

When a lender accepts a repo, they receive actual title to the basket securities. Those securities are now in the lender's wallet. This means the lender can use those securities — specifically, they can pledge them as collateral in a *new* repo, borrowing additional cash from a third party.

Consider the flow: a Prime Broker pledges a basket worth $1,200 to Citadel and borrows $1,000. Citadel now holds title to the basket, plus a RepoToken (an ERC-721) representing their lender position. Citadel can then pledge that RepoToken to Jupiter and borrow an additional $800. From a single $1,200 basket, the system has generated $1,800 in total funding — a capital efficiency of 1.5x, compared to approximately 0.5x in a typical lending pool.

However, rehypothecation carries systemic risk. Uncontrolled chains of rehypothecation were a contributing factor to the 2008 financial crisis, where the same collateral was pledged so many times that unwinding became impossible. This is why SEC Rule 15c3-3 exists: it caps the total amount a broker-dealer can rehypothecate at 140% of the customer's debit balance (indebtedness).

In traditional finance, this 140% cap is enforced through audits, compliance officers, and periodic reporting. Violations are discovered after the fact. On our protocol, the cap is enforced at the smart contract level — the `proposeRehypo` function checks `principal <= 140% × original_repo_principal` and reverts if exceeded. It is impossible to breach the regulatory limit, not because of a compliance department, but because of code.

This is a fundamental advantage of on-chain securities financing: blockchain transparency doesn't just enable rehypothecation — it makes it verifiable, enforceable, and regulatable in real time for the first time.

### Manufactured Payment — Clean Dividend Handling

Equities pay dividends. This creates a complication that does not exist for crypto tokens: during the repo term, the lender holds legal title to the securities, but the borrower is economically entitled to any dividend payments. In traditional finance, the solution is a manufactured payment — the lender, who receives the actual dividend (because they hold title), owes an equivalent payment to the borrower.

Our smart contract handles this automatically. When the protocol owner (or, in production, a Chainlink oracle) calls `distributeDividend`, the contract calculates the total dividend amount based on the number of shares in the basket and records it as a credit against the borrower's settlement obligation. At maturity, the net payment formula is:

```
Net Payment = Principal + Accrued Interest − Manufactured Payment Credit
```

The tax treatment is also clean and unambiguous. The lender holds title during the record date, so they are the legal recipient of the dividend for tax purposes. The manufactured payment from lender to borrower is a separate, clearly categorized transaction. Both parties have well-defined tax positions.

Compare this to a lending pool, where the vault holds the tokens during a dividend event. Who is the legal recipient? The vault is a smart contract, not a legal entity. The borrower deposited the tokens, but they don't hold title. The lender provided cash but never took possession of the securities. The ownership — and therefore the tax obligation — is ambiguous. This ambiguity is unacceptable for institutional participants.

### Cascade Detection — Transparent Risk Management

When multiple layers of rehypothecation exist, unwinding one layer affects all downstream positions. If a base repo settles and the original RepoToken is burned, any position that used that RepoToken as collateral suddenly has no backing.

Our protocol handles this automatically. When `settleRepo` burns a RepoToken, the contract checks if that token was used as collateral in a downstream rehypo. If so, it triggers an automatic margin call on the downstream position, giving the borrower a grace period to either settle or provide new collateral.

In traditional finance, this cascade risk exists but is largely invisible — participants may not know how many times their collateral has been re-pledged downstream. On-chain, the entire chain is visible to all parties. Jupiter, holding a rehypothecated position, can inspect the full chain at any time: who posted the original basket, what securities are in it, what the current margin health is, and whether the 140% cap is being respected. This level of transparency simply does not exist in traditional securities financing.

---

## Architecture

### Contract Structure

```
src/
├── core/
│   ├── BasketManager.sol    # Basket creation, valuation, haircut calculation
│   ├── RepoServicer.sol     # Full lifecycle engine
│   ├── RepoToken.sol        # ERC-721 position token
│   ├── RepoMarket.sol       # Lender registry, proposal listing
│   └── RepoTypes.sol        # Shared types, events, errors
├── mocks/
│   ├── MockToken.sol        # ERC-20 for USDC and stock tokens (local testing)
│   └── MockPriceFeed.sol    # Owner-settable price oracle
script/
├── Config.sol               # Network-specific addresses
├── DeployLocal.s.sol        # Local anvil deployment
└── DeployRobinhood.s.sol    # Robinhood Chain testnet deployment
test/
└── RepoServicer.t.sol       # 8 test cases covering full lifecycle
```

### Contract Interactions

```
                    ┌─────────────┐
                    │ RepoMarket  │
                    │ - register  │
                    │ - list      │
                    └──────┬──────┘
                           │
    ┌──────────────────────┼──────────────────────┐
    │                      │                      │
    ▼                      ▼                      ▼
┌────────┐         ┌──────────────┐        ┌───────────┐
│Borrower│         │ RepoServicer │        │  Lender   │
│  (PB)  │────────>│              │<───────│ (Citadel) │
└────────┘         │ propose      │        └───────────┘
                   │ accept       │
                   │ margin call  │
                   │ top up       │
                   │ settle       │
                   │ rehypo       │
                   └──────┬───────┘
                          │
               ┌──────────┼──────────┐
               ▼          ▼          ▼
        ┌───────────┐ ┌───────┐ ┌──────────┐
        │BasketMgr  │ │RepoTkn│ │PriceFeed │
        │- create   │ │ERC-721│ │- getPrice│
        │- value    │ │- mint │ │- setPrice│
        │- params   │ │- burn │ │          │
        └───────────┘ └───────┘ └──────────┘
```

### State Machine

```
                  propose
    ┌──────────────────────────────┐
    │                              ▼
    │   ┌──────────┐        ┌──────────┐
    │   │          │ accept │          │
    └───│ Proposed │───────>│  Active  │◄────────┐
        └──────────┘        └────┬─────┘         │
                                 │               │
                    checkMargin  │     topUp     │
                    (below 40%)  │   (above 60%) │
                                 ▼               │
                          ┌──────────────┐       │
                          │ MarginCalled │───────┘
                          └──────┬───────┘
                                 │ grace expired
                                 ▼
                          ┌──────────────┐
                          │  Liquidated  │
                          └──────────────┘

        ┌──────────┐ checkMaturity ┌──────────┐ settle ┌──────────┐
        │  Active  │──────────────>│  Matured │───────>│  Settled │
        └──────────┘               └──────────┘        └──────────┘
```

### Rehypothecation Flow

```
    Prime Broker              Citadel Capital            Jupiter MMF
    (Borrower)                (Lender → Rehypo Borrower) (Rehypo Lender)
        │                            │                        │
        │── proposeRepo ────────────>│                        │
        │   basket: TSLA+AMZN+AMD   │                        │
        │                            │                        │
        │<── acceptRepo ────────────│                        │
        │   basket → Citadel         │                        │
        │   USDC → PB                │                        │
        │   RT #1 minted → Citadel   │                        │
        │                            │                        │
        │                            │── proposeRehypo ──────>│
        │                            │   collateral: RT #1    │
        │                            │   cap: 140% ✓          │
        │                            │                        │
        │                            │<── acceptRehypo ──────│
        │                            │   RT #1 → Jupiter      │
        │                            │   USDC → Citadel       │
        │                            │   RT #2 → Jupiter      │
        │                            │                        │
   [Day 14]                          │                        │
        │                            │── settleRehypo ───────>│
        │                            │   USDC + interest      │
        │                            │   RT #1 returned       │
        │                            │   RT #2 burned         │
        │                            │                        │
   [Day 30]                          │                        │
        │── settleRepo ─────────────>│                        │
        │   USDC + interest - mfg    │                        │
        │   basket returned          │                        │
        │   RT #1 burned             │                        │
```

### Settlement Math

```
Net Payment = Principal + Accrued Interest − Manufactured Payment Credit

Accrued Interest = Principal × Rate × Elapsed / (10000 × 365 days)
Manufactured Payment = Σ (dividend per share × shares in basket)

Example (30-day repo):
  Principal:     $1,000.00
  Rate:          4.80% (480 bps)
  Interest:      $1,000 × 480/10000 × 30/365 = $3.95
  Mfg Payment:   TSLA $2.50/share × 2 shares = $5.00
  Net Payment:   $1,000 + $3.95 − $5.00 = $998.95
```

### Margin Health

```
Health = (Basket Value − Principal) / Basket Value × 10000

Thresholds:
  > 60%  → Healthy
  40-60% → Warning
  < 40%  → Margin Call (24h grace period)
  < 20%  → Liquidation eligible
```

---

## Deployment

### Robinhood Chain Testnet

**Existing Robinhood Tokens (used as collateral):**
| Token | Address |
|-------|---------|
| WETH | `0x7943e237c7F95DA44E0301572D358911207852Fa` |
| TSLA | `0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E` |
| AMZN | `0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02` |
| PLTR | `0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0` |
| NFLX | `0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93` |
| AMD  | `0x71178BAc73cBeb415514eB542a8995b82669778d` |

**Deployed by us:**
| Contract | Address |
|----------|---------|
| USDC (Mock) | `0x7B44d68015E31B647d1719Df52B37dF392621186` |
| PriceFeed | `0x712F5833EdE96f6E2fFDA5f2eac4B5509E18DF08` |
| BasketManager | `0x06291Aac93CBaaf332256F9F874698eFE25caa1E` |
| RepoToken | `0x7bbD046e69F7BE03E4b7DC50e421541E9f787aF1` |
| RepoMarket | `0xd49c0A7adA0199b8c20AD19Ae9D3688D6AcbcD19` |
| RepoServicer | `0xCB8F577d61Ff3075568303283C76518eF254fAc6` |

### Local Testing

```bash
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit
forge build --via-ir
forge test -vvv
```

8 tests passing: basket creation, haircut calculation, full lifecycle, margin call + top up, rehypothecation, rehypo cap enforcement, liquidation, settlement math.

---

## Frontend

Single HTML file with ethers.js v6 and MetaMask integration. All actions execute real on-chain transactions on Robinhood Chain testnet.

Three wallet roles:
- **Prime Broker** — Creates baskets, proposes repos, settles
- **Citadel Capital** — Accepts repos, rehypothecates
- **Jupiter MMF** — Accepts rehypo, views chain transparency

---

## Future Work: Cross-Chain DvP with LayerZero

### The Problem

Stock tokens live on Robinhood Chain. The deepest USDC liquidity lives on Arbitrum. Institutions should not have to bridge cash across chains to finance securities. Securities should stay where they're issued. Cash should stay where the liquidity is.

### The Solution: Delivery versus Payment

```
┌─────────────────────┐                        ┌─────────────────────┐
│   Robinhood Chain    │                        │      Arbitrum       │
│   Securities Leg     │                        │      Cash Leg       │
│                      │                        │                     │
│  ┌────────────────┐  │     ┌────────────┐     │  ┌────────────────┐ │
│  │ Escrow Contract│  │     │            │     │  │ Mirror Escrow  │ │
│  │ TSLA+AMZN+AMD  │◄─┼─────│  LayerZero │─────┼─►│    USDC        │ │
│  │    locked      │  │     │            │     │  │    locked      │ │
│  └───────┬────────┘  │     │  Verify    │     │  └───────┬────────┘ │
│          │           │     │  Both Locks│     │          │          │
│          ▼           │     │     ↓      │     │          ▼          │
│  Release to Lender   │     │  Atomic    │     │  Release to        │
│                      │     │  Release   │     │  Borrower          │
└─────────────────────┘     └────────────┘     └─────────────────────┘

                    Either side fails → both revert
```

### Workflow

1. **Borrower locks basket** → Escrow contract on Robinhood Chain
2. **Lender locks USDC** → Mirror escrow on Arbitrum
3. **LayerZero verifies** both locks via cross-chain message
4. **Simultaneous release** → Securities to lender, cash to borrower
5. **At maturity** → Reverse process with same atomic guarantee

### Why Each Chain

- **Robinhood Chain**: Settlement layer for tokenized securities — where stock tokens are issued
- **Arbitrum**: Cash leg — deepest USDC/DeFi liquidity in the Ethereum ecosystem
- **LayerZero**: Cross-chain messaging enabling atomic DvP across both chains

Our contracts are architected to support this. This is our next development milestone.

---

## Why Repo, Not Pools

| | Pool (Aave/Compound) | Equity Repo (Ours) |
|---|---|---|
| **Tax** | Deposit = sale = capital gains | Financing = no disposal = no tax |
| **Collateral** | Single token, locked in vault | Basket, title transfer to lender |
| **Diversification** | None | Weighted haircut + bonus |
| **Capital Efficiency** | ~0.5x (locked) | ~1.5x (rehypothecation) |
| **Dividends** | Ambiguous ownership | Manufactured payment, clean tax |
| **Rehypothecation** | Not possible | Title transfer enables re-pledge |
| **Regulation** | N/A | SEC 15c3-3 140% cap on-chain |
| **Leverage Visibility** | N/A | Full chain transparency |
| **Maturity** | Open-term | Fixed term, yield curve possible |
| **Rate** | Floating (utilization) | Fixed repo rate |

---

## License

MIT
