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
    uint256 initVirtualEthReserve = 0.0001 ether;

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

contract TestnetTransactionScript is Script {
    RampBondingCurveAMM curve;
    uint256 threshold;
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    function setCurve() public virtual {
        curve = RampBondingCurveAMM(payable(0xD62BfbF2050e8fEAD90e32558329D43A6efce4C8));
    }

    function setThreshold() public virtual {
        threshold = 0.0003 ether;
    }

    function runTokenLaunch() public returns (RampToken) {
        TokenLaunchParam memory param = TokenLaunchParam({
            name: "Ramp Token",
            symbol: "RTK",
            description: "Community token for ramp.fun",
            image: "ramp.jpg",
            twitterLink: "x.com/ramp.fun",
            telegramLink: "t.me/ramp.fun",
            website: "https://ramp-fun.vercel.app"
        });
        address token = curve.launchToken(param);
        return RampToken(token);
    }

    function runSwapEthForTokens(RampToken token, uint256 amountIn) public returns (uint256 amountOut) {
        uint256 amountOutMin = curve.calcAmountOutFromEth(address(token), amountIn);
        amountOut = curve.swapEthForTokens{ value: amountIn }(address(token), amountIn, amountOutMin, block.timestamp + 2 minutes);
    }

    function runSwapTokensForEth(RampToken token, uint256 amountIn) public returns (uint256 amountOut) {
        uint256 amountOutMin = curve.calcAmountOutFromToken(address(token), amountIn);
        token.approve(address(curve), amountIn);
        amountOut = curve.swapTokensForEth(address(token), amountIn, amountOutMin, block.timestamp + 2 minutes);
    }

    function runMigrateLiquidity(RampToken token) public {
        uint256 amountOutMin = curve.calcAmountOutFromEth(address(token), threshold);
        curve.swapEthForTokens{ value: threshold }(address(token), threshold, amountOutMin, block.timestamp + 2 minutes);
    }

    function run() public {
        setCurve();
        setThreshold();
        vm.startBroadcast(deployerPrivateKey);
        curve.setCreationFee(0);
        RampToken token = runTokenLaunch();
        uint256 tokenAmountOut = runSwapEthForTokens(token, 0.0001 ether);
        runSwapTokensForEth(token, tokenAmountOut/2);
        runMigrateLiquidity(token);
        vm.stopBroadcast();
    }
}

contract MainnetTransactionScript is TestnetTransactionScript {
    function setCurve() public override {
        curve = RampBondingCurveAMM(payable(0xD62BfbF2050e8fEAD90e32558329D43A6efce4C8));
    }
    function setThreshold() public override {
        threshold = 0.0003 ether;
    }
}