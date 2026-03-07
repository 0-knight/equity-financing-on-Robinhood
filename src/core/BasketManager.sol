// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./RepoTypes.sol";
import "../mocks/MockPriceFeed.sol";

contract BasketManager {
    MockPriceFeed public priceFeed;

    uint256 public nextBasketId = 1;
    mapping(uint256 => RepoTypes.Basket) public baskets;

    // Diversification bonus per extra asset (115 = 1.15%)
    uint256 public constant DIV_BONUS_PER_ASSET = 115;
    uint256 public constant MIN_HAIRCUT = 500; // 5% in basis points
    uint256 public constant BASIS = 10000;

    constructor(address _priceFeed) {
        priceFeed = MockPriceFeed(_priceFeed);
    }

    function createBasket(
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (uint256 basketId) {
        require(tokens.length > 0 && tokens.length == amounts.length, "Invalid input");
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Zero amount");
        }

        basketId = nextBasketId++;
        baskets[basketId] = RepoTypes.Basket({
            tokens: tokens,
            amounts: amounts,
            creator: msg.sender,
            timestamp: block.timestamp
        });

        emit BasketCreated(basketId, msg.sender, tokens, amounts);
    }

    function getBasket(uint256 basketId) external view returns (
        address[] memory tokens,
        uint256[] memory amounts,
        address creator
    ) {
        RepoTypes.Basket storage b = baskets[basketId];
        require(b.creator != address(0), "Basket not found");
        return (b.tokens, b.amounts, b.creator);
    }

    function getBasketValue(uint256 basketId) public view returns (uint256) {
        RepoTypes.Basket storage b = baskets[basketId];
        require(b.creator != address(0), "Basket not found");
        return priceFeed.getBasketValue(b.tokens, b.amounts);
    }

    /// @notice Calculate haircut parameters for a basket
    /// @return haircut in basis points
    /// @return marginThreshold in basis points (80% of haircut level)
    /// @return maxBorrow in USDC (6 decimals)
    function calculateParams(
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external view returns (
        uint256 haircut,
        uint256 marginThreshold,
        uint256 maxBorrow
    ) {
        require(tokens.length > 0 && tokens.length == amounts.length, "Invalid input");

        uint256 totalValue = priceFeed.getBasketValue(tokens, amounts);
        require(totalValue > 0, "Zero basket value");

        // Weighted average volatility
        uint256 weightedVol = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenValue = (priceFeed.getPrice(tokens[i]) * amounts[i]) / 1e20;
            uint256 vol = priceFeed.getVolatility(tokens[i]);
            weightedVol += (tokenValue * vol);
        }
        uint256 avgVol = weightedVol / totalValue;

        // Diversification bonus: (numAssets - 1) * 1.15%
        uint256 divBonus = 0;
        if (tokens.length > 1) {
            divBonus = (tokens.length - 1) * DIV_BONUS_PER_ASSET;
        }

        // Final haircut = max(5%, avgVol - divBonus)
        if (avgVol > divBonus + MIN_HAIRCUT) {
            haircut = avgVol - divBonus;
        } else {
            haircut = MIN_HAIRCUT;
        }

        // Margin threshold = haircut * 80%
        marginThreshold = (haircut * 80) / 100;

        // Max borrow = totalValue * (1 - haircut)
        maxBorrow = (totalValue * (BASIS - haircut)) / BASIS;
    }

    /// @notice Add more of an existing token to a basket (top up)
    function addToBasket(uint256 basketId, address token, uint256 amount) external {
        RepoTypes.Basket storage b = baskets[basketId];
        require(b.creator != address(0), "Basket not found");

        bool found = false;
        for (uint256 i = 0; i < b.tokens.length; i++) {
            if (b.tokens[i] == token) {
                b.amounts[i] += amount;
                found = true;
                break;
            }
        }
        require(found, "Token not in basket");

        emit BasketToppedUp(basketId, token, amount);
    }

    function getBasketTokenCount(uint256 basketId) external view returns (uint256) {
        return baskets[basketId].tokens.length;
    }
}
