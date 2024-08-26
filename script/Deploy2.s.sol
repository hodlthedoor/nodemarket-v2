// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/OtcExchange_V2.sol";
import "src/token.sol";

// forge script script/Deploy2.s.sol:Deploy2Script --private-key $PRIVATE_KEY --rpc-url $RPC_URL -vv --legacy --verify --etherscan-api-key $ETHERSCAN_API_KEY

contract Deploy2Script is Script {
    function setUp() public {}

    function run() public {

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address commissionAddress = msg.sender;
        OtcExchange_V2 exchange = new OtcExchange_V2(commissionAddress);

        token token1 = new token("token1", "token1", 100 ether);
        token token2 = new token("token2", "token2", 100 ether);

        bool isApproved = true;

        exchange.updateSaleToken(address(token1), isApproved);
        exchange.updatePaymentToken(address(token2), isApproved);

        token1.approve(address(exchange), 100 ether);


        /*
            Exchange address:  0x9e8F8d283a300AAdFf967504903eeC57B5D168Bb
            Token1 address:  0x74348eE5375463FC1Cb2f5fC1C9A2cCCe23f79Ee
            Token2 address:  0x9DF3350b265F8b5248Fd3F7c1d701DB1E7Ad7f35
            expiry time: " 1722971820
        */
        



    }
}
