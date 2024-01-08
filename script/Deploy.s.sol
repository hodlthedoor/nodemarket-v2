// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/OtcExchange_V2.sol";

// forge script script/Deploy.s.sol:DeployScript --private-key $PRIVATE_KEY --rpc-url $RPC_URL --broadcast -vv

contract DeployScript is Script {
    function setUp() public {}

    function run() public {

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address commissionAddress = msg.sender;
        new OtcExchange_V2(commissionAddress);


    }
}
