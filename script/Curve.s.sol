// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";
import "../src/Curve.sol";

contract TestnetDeploymentScript is Script {

    address feeCollector = 0xF65330dC75e32B20Be62f503a337cD1a072f898f;
    address swapRouter;
    address fraxswapFactory;
    uint256 tradingFeeRate = 100; // 1%
    uint256 migrationFeeRate = 500; // 5%
    uint256 creationFee = 10**15; // 0.001 ether
    uint256 initVirtualEthReserve = 0.03 ether;

    function setRouterAndFactory() public virtual {
        swapRouter = 0x938d99A81814f66b01010d19DDce92A633441699;
        fraxswapFactory = 0xcA35C3FE456a87E6CE7827D1D784741613463204;

    }

    function run() public {
        setRouterAndFactory();
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        RampBondingCurveAMM curve = new RampBondingCurveAMM(
            tradingFeeRate, migrationFeeRate, 
            creationFee, initVirtualEthReserve, 
            feeCollector, swapRouter, fraxswapFactory
        );
        console.log("Curve Address: ", address(curve));
        vm.stopBroadcast();
    }
}

contract MainnetDeploymentScript is TestnetDeploymentScript {
    function setRouterAndFactory() public override {
        swapRouter = 0x39cd4db6460d8B5961F73E997E86DdbB7Ca4D5F6;
        fraxswapFactory = 0xE30521fe7f3bEB6Ad556887b50739d6C7CA667E6;
    }
}