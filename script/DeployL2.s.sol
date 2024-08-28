// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {L2HypercycleLicence} from "src/L2/L2HypercycleLicence.sol";
import {L2HypercycleToken} from "src/L2/L2HypercycleToken.sol";
import {L2HypercycleShareTokensV2} from "src/L2/L2HyperCycleShareTokensV2.sol";
import {HyperCycleSwapV2} from "src/core/HyperCycleSwapV2.sol";

// forge script script/DeployL2.s.sol:DeployL2Script --private-key $PRIVATE_KEY --rpc-url $RPC_URL --legacy --verify --etherscan-api-key $ETHERSCAN_API_KEY --broadcast -vv

contract DeployL2Script is Script {

    bool constant private DEBUG = true;

    error UnsupportedChain(uint256 chainId);
    function setUp() public {}

    function run() public {

        if(!DEBUG) {
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        }
        else {
            vm.startPrank(vm.addr(vm.envUint("PRIVATE_KEY")));
            console.log("DEBUG MODE");
        }

        address bridge;
        address remoteToken;
        uint256 remoteChainId;
        address remoteErc20Token;

        // sepolia - nft bridge - 0x4200000000000000000000000000000000000014
        // sepolia - hypercycle licence - 0xa1A874b461056d7dBe6fEB31f2a8c5301A4879Dd
        // sepolia - hypc erc20 - 0x420
        // sepolia - remote chain id - 0xaa36a7

        // mainnet - nft bridge - 0x4200000000000000000000000000000000000014
        // mainnet - hypc erc20 - 0xeA7B7DC089c9a4A916B5a7a37617f59fD54e37E4
        // mainnet - hypercycle licence - 0xd32CB5f76989A27782e44c5297AAba728Ad61669
        // mainnet - swapv2 - 0x21468e63abF3783020750F7b2e57d4B34aFAfba6 (current root token id = 67109152) (67108864 + 4095)
        // mainnet - remote chain id - 0x01


        if (block.chainid == 10) { // Optimism Sepolia
            bridge = 0x4200000000000000000000000000000000000014;
            remoteToken = 0xa1A874b461056d7dBe6fEB31f2a8c5301A4879Dd; // HyperCycle License on Sepolia
            remoteChainId = 0xaa36a7; // Sepolia chain ID
            remoteErc20Token = 0x5a3A8238f9A0564b30B90AF267146504FCc303F1; // HyPC ERC20 on Sepolia
        } else if (block.chainid == 11155420) { // Optimism Mainnet
            bridge = 0x4200000000000000000000000000000000000014;
            remoteToken = 0xd32CB5f76989A27782e44c5297AAba728Ad61669; // HyperCycle License on Mainnet
            remoteChainId = 0x01; // Mainnet chain ID
            remoteErc20Token = 0xeA7B7DC089c9a4A916B5a7a37617f59fD54e37E4; // HyPC ERC20 on Mainnet
        } else {
            revert UnsupportedChain(block.chainid);
        }

        console.log("Deploying on chain: ", block.chainid);



        L2HypercycleLicence hypcLicense = new L2HypercycleLicence(bridge, remoteToken, remoteChainId);

        uint256 startSwapV2 = 67108864 + 2048; // = 67110912. like 50% of the total root token supply
        uint256 endSwapV2 = 67108864 + 4095;


        HyperCycleSwapV2 hypcSwapV2 = new HyperCycleSwapV2(

            address(hypcLicense),
            startSwapV2,
            endSwapV2);

        L2HypercycleToken hypcToken = new L2HypercycleToken(bridge, remoteErc20Token);
        
        // mainnet
        // HypercycleShareTokenV2 start number = 8590983168
        // HypercycleShareTokenV2 end number = 8592031743

        L2HypercycleShareTokensV2 shareTokens = new L2HypercycleShareTokensV2(
            8592031744,        // New startNumber (next block)
            8593080319,        // New endNumber (next block)
            8592031744,        // New startLimit (initial limit)
            address(hypcLicense),
            address(hypcSwapV2),
            address(hypcToken)
        );

        console.log("Deployer address: ", msg.sender);
        console.log("HyperCycle Licence address: ", address(hypcLicense));
        console.log("HyperCycle Swap V2 address: ", address(hypcSwapV2));
        console.log("HyperCycle Token address: ", address(hypcToken));
        console.log("HyperCycle Share Tokens V2 address: ", address(shareTokens));

    }
}
