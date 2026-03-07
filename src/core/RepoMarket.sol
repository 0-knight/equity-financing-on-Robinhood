// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./RepoTypes.sol";

contract RepoMarket {
    mapping(address => RepoTypes.LenderProfile) public lenders;
    address[] public lenderList;

    uint256[] public openProposals;
    mapping(uint256 => bool) public isProposalOpen;

    // lender => list of proposal repoIds directed to them
    mapping(address => uint256[]) public proposalsForLender;

    function registerLender(uint256 minRate, uint256 maxMaturity) external {
        if (!lenders[msg.sender].isRegistered) {
            lenderList.push(msg.sender);
        }
        lenders[msg.sender] = RepoTypes.LenderProfile({
            minRate: minRate,
            maxMaturity: maxMaturity,
            completedRepos: lenders[msg.sender].completedRepos,
            totalVolume: lenders[msg.sender].totalVolume,
            isRegistered: true
        });

        emit LenderRegistered(msg.sender, minRate, maxMaturity);
    }

    function listProposal(uint256 repoId, address lender) external {
        openProposals.push(repoId);
        isProposalOpen[repoId] = true;
        proposalsForLender[lender].push(repoId);

        emit ProposalListed(repoId);
    }

    function removeProposal(uint256 repoId) external {
        isProposalOpen[repoId] = false;
    }

    function recordCompletion(address lender, uint256 volume) external {
        lenders[lender].completedRepos++;
        lenders[lender].totalVolume += volume;
    }

    // ── View functions ──

    function getActiveLenders() external view returns (address[] memory) {
        return lenderList;
    }

    function getLenderTerms(address lender) external view returns (uint256 minRate, uint256 maxMaturity) {
        RepoTypes.LenderProfile storage p = lenders[lender];
        return (p.minRate, p.maxMaturity);
    }

    function getLenderStats(address lender) external view returns (uint256 completedRepos, uint256 totalVolume) {
        RepoTypes.LenderProfile storage p = lenders[lender];
        return (p.completedRepos, p.totalVolume);
    }

    function getOpenProposals() external view returns (uint256[] memory) {
        // Return only still-open ones
        uint256 count = 0;
        for (uint256 i = 0; i < openProposals.length; i++) {
            if (isProposalOpen[openProposals[i]]) count++;
        }
        uint256[] memory result = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < openProposals.length; i++) {
            if (isProposalOpen[openProposals[i]]) {
                result[idx++] = openProposals[i];
            }
        }
        return result;
    }

    function getProposalsForLender(address lender) external view returns (uint256[] memory) {
        return proposalsForLender[lender];
    }
}
