// Contract addresses on Robinhood Chain Testnet
const CONFIG = {
  rpc: "https://rpc.testnet.chain.robinhood.com/",
  chainId: 46630, // Robinhood Chain Testnet

  // Existing RH tokens
  TSLA: "0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E",
  AMZN: "0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02",
  AMD:  "0x71178BAc73cBeb415514eB542a8995b82669778d",
  NFLX: "0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93",
  PLTR: "0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0",

  // Deployed by us
  USDC:          "0x2490329a6c4b8FB76dA3949A58F4d5A5DA084196",
  PriceFeed:     "0x862EA42EF2A6E2Ecc6F14A2Fd8C75CaC0960f7f5",
  BasketManager: "0xecA4c967c0E67b5FB5d97b5703f3B68e8beb7277",
  RepoToken:     "0xfa8209cD0DD34B9bB434DB0D4c979D2166032203",
  RepoMarket:    "0xE57afa43F0AAf01b7974463f20eb84E8028501E6",
  RepoServicer:  "0xa6171F5C434f5EA5135fBc24Eb92bbd6D530af06",

  // Known wallets
  wallets: {
    "0x0D781453255A7Dbdf7F431CbCB956733173898b5": "Prime Broker",
    "0x3FB2d86389bea9f673F6Fc9d9FD4AE549A2f2eB1": "Citadel Capital",
    "0x6F217c0bA23D54330E38A9Ee917455659e4d597d": "Jupiter MMF",
  },

  // Token metadata
  tokens: {
    "0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E": { symbol: "TSLA", name: "Tesla, Inc.", decimals: 18 },
    "0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02": { symbol: "AMZN", name: "Amazon.com", decimals: 18 },
    "0x71178BAc73cBeb415514eB542a8995b82669778d": { symbol: "AMD",  name: "AMD, Inc.", decimals: 18 },
    "0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93": { symbol: "NFLX", name: "Netflix, Inc.", decimals: 18 },
    "0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0": { symbol: "PLTR", name: "Palantir Tech.", decimals: 18 },
    "0x2490329a6c4b8FB76dA3949A58F4d5A5DA084196": { symbol: "USDC", name: "USD Coin", decimals: 6 },
  }
};

// Minimal ABIs
const ABI = {
  ERC20: [
    "function balanceOf(address) view returns (uint256)",
    "function approve(address,uint256) returns (bool)",
    "function transfer(address,uint256) returns (bool)",
    "function allowance(address,address) view returns (uint256)",
    "function decimals() view returns (uint8)",
    "function symbol() view returns (string)",
  ],

  ERC721: [
    "function balanceOf(address) view returns (uint256)",
    "function ownerOf(uint256) view returns (address)",
    "function setApprovalForAll(address,bool)",
    "function isApprovedForAll(address,address) view returns (bool)",
  ],

  PriceFeed: [
    "function getPrice(address) view returns (uint256)",
    "function setPrice(address,uint256)",
    "function getVolatility(address) view returns (uint256)",
    "function setVolatility(address,uint256)",
    "function getBasketValue(address[],uint256[]) view returns (uint256)",
  ],

  BasketManager: [
    "function createBasket(address[],uint256[]) returns (uint256)",
    "function getBasket(uint256) view returns (address[],uint256[],address)",
    "function getBasketValue(uint256) view returns (uint256)",
    "function calculateParams(address[],uint256[]) view returns (uint256,uint256,uint256)",
    "function addToBasket(uint256,address,uint256)",
    "function getBasketTokenCount(uint256) view returns (uint256)",
    "function nextBasketId() view returns (uint256)",
  ],

  RepoServicer: [
    "function proposeRepo(uint256,uint256,uint256,uint256,address) returns (uint256)",
    "function acceptRepo(uint256)",
    "function distributeDividend(uint256,address,uint256)",
    "function checkMargin(uint256)",
    "function topUpCollateral(uint256,address,uint256)",
    "function substituteCollateral(uint256,address,uint256,address,uint256)",
    "function checkMaturity(uint256)",
    "function settleRepo(uint256)",
    "function liquidate(uint256)",
    "function proposeRehypo(uint256,uint256,uint256,uint256,address) returns (uint256)",
    "function acceptRehypo(uint256)",
    "function settleRehypo(uint256)",
    "function debugSetMaturity(uint256,uint256)",
    "function debugSetState(uint256,uint8)",
    "function getRepoState(uint256) view returns (uint8)",
    "function getRepoTerms(uint256) view returns (uint256,uint256,uint256,uint256)",
    "function calculateAccruedInterest(uint256) view returns (uint256)",
    "function getMfgPaymentCredit(uint256) view returns (uint256)",
    "function calculateSettlement(uint256) view returns (uint256,uint256,uint256,uint256)",
    "function getMarginHealth(uint256) view returns (uint256)",
    "function isMarginCalled(uint256) view returns (bool)",
    "function getGraceDeadline(uint256) view returns (uint256)",
    "function getMaturityDate(uint256) view returns (uint256)",
    "function getRehypoCap(uint256) view returns (uint256)",
    "function getRehypoChain(uint256) view returns (uint256[])",
    "function getReposByBorrower(address) view returns (uint256[])",
    "function getReposByLender(address) view returns (uint256[])",
    "function nextRepoId() view returns (uint256)",
  ],

  RepoToken: [
    "function balanceOf(address) view returns (uint256)",
    "function ownerOf(uint256) view returns (address)",
    "function setApprovalForAll(address,bool)",
    "function isApprovedForAll(address,address) view returns (bool)",
    "function getRepoTokenInfo(uint256) view returns (tuple(uint256 repoId, uint256 principal, uint256 repoRate, uint256 maturityDate, uint256 basketId, uint8 collateralType, uint256 parentTokenId, bool isActive))",
    "function isRehypoAvailable(uint256) view returns (bool)",
    "function getRehypoCap(uint256) view returns (uint256)",
    "function getCollateralType(uint256) view returns (uint8)",
    "function nextTokenId() view returns (uint256)",
    "function rehypoOf(uint256) view returns (uint256)",
  ],

  RepoMarket: [
    "function registerLender(uint256,uint256)",
    "function getActiveLenders() view returns (address[])",
    "function getLenderTerms(address) view returns (uint256,uint256)",
    "function getLenderStats(address) view returns (uint256,uint256)",
    "function getOpenProposals() view returns (uint256[])",
    "function getProposalsForLender(address) view returns (uint256[])",
  ],
};
