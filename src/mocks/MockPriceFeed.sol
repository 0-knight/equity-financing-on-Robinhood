// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MockPriceFeed is Ownable {
    // token => price in USD (8 decimals, e.g. 26700000000 = $267.00)
    mapping(address => uint256) public prices;
    // token => volatility in basis points (2000 = 20%)
    mapping(address => uint256) public volatilities;

    constructor() Ownable(msg.sender) {}

    function setPrice(address token, uint256 price) external onlyOwner {
        prices[token] = price;
    }

    function setPrices(address[] calldata tokens, uint256[] calldata _prices) external onlyOwner {
        require(tokens.length == _prices.length, "Length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            prices[tokens[i]] = _prices[i];
        }
    }

    function setVolatility(address token, uint256 vol) external onlyOwner {
        volatilities[token] = vol;
    }

    function setVolatilities(address[] calldata tokens, uint256[] calldata vols) external onlyOwner {
        require(tokens.length == vols.length, "Length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            volatilities[tokens[i]] = vols[i];
        }
    }

    function getPrice(address token) external view returns (uint256) {
        require(prices[token] > 0, "Price not set");
        return prices[token];
    }

    function getVolatility(address token) external view returns (uint256) {
        return volatilities[token];
    }

    /// @notice Calculate total value of a basket of tokens
    /// @return value Total value in USD (6 decimals for USDC compatibility)
    function getBasketValue(
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external view returns (uint256 value) {
        require(tokens.length == amounts.length, "Length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            // price is 8 decimals, amount is 18 decimals (ERC-20)
            // value in 6 decimals = price * amount / 1e20
            value += (prices[tokens[i]] * amounts[i]) / 1e20;
        }
    }
}
