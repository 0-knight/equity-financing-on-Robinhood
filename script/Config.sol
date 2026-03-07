// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library NetworkConfig {
    struct Config {
        address weth;
        address tsla;
        address amzn;
        address pltr;
        address nflx;
        address amd;
        address usdc;  // we deploy our own MockUSDC since RH testnet doesn't have one
    }

    /// @notice Robinhood Chain Testnet (chainId: TBD)
    function getRobinhoodTestnet() internal pure returns (Config memory) {
        return Config({
            weth: 0x7943e237c7F95DA44E0301572D358911207852Fa,
            tsla: 0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E,
            amzn: 0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02,
            pltr: 0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0,
            nflx: 0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93,
            amd:  0x71178BAc73cBeb415514eB542a8995b82669778d,
            usdc: address(0) // will be deployed
        });
    }

    /// @notice Local Foundry test (anvil) — all addresses are zero, mocks will be deployed
    function getLocal() internal pure returns (Config memory) {
        return Config({
            weth: address(0),
            tsla: address(0),
            amzn: address(0),
            pltr: address(0),
            nflx: address(0),
            amd:  address(0),
            usdc: address(0)
        });
    }
}
