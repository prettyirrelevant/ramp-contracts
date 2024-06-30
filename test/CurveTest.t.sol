// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console, Vm} from "forge-std/Test.sol";
import { RampToken } from "../src/Token.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import "../src/Curve.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract BaseForkTest is Test {

    RampBondingCurveAMM public curve;
    RampToken public testToken;
    address public feeCollector;
    address public trader;
    address public admin;
    address public swapRouter;
    address public uniswapV2Factory;
    uint256 tradingFeeRate = 100; // 1%
    uint256 migrationFeeRate = 700; // 1.5%
    uint256 creationFee = 10**15; // 0.001 ether
    uint256 initVirtualEthReserve = 0.03 ether;

    function setRouterAndFactory() public virtual {
        swapRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
        uniswapV2Factory = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
    }

    function runSetUp() internal {
        (feeCollector, ) = makeAddrAndKey("feeCollector");
        (trader, ) = makeAddrAndKey("trader");
        (admin, ) = makeAddrAndKey("admin");
        vm.prank(admin);
        curve = new RampBondingCurveAMM(
            tradingFeeRate, 
            migrationFeeRate, 
            creationFee, 
            initVirtualEthReserve,
            feeCollector,
            swapRouter,
            uniswapV2Factory
        );
        TokenLaunchParam memory param = TokenLaunchParam({
            name: "Test Token",
            symbol: "TTK",
            description: "Token launch for testing purpose",
            image: "image.jpg",
            twitterLink: "x.com/test",
            telegramLink: "t.me/test",
            website: "test.com"
        });
        address token = curve.launchToken{value: creationFee}(param);
        testToken = RampToken(token);
    }
    
    function setUp() public {
        setRouterAndFactory();
        runSetUp();
    }
}

contract MainnetForkTest is BaseForkTest {
    using FixedPointMathLib for uint256;

    function test_contract_variables() public view {
        assertEq(curve.admin(), admin);
        assertEq(curve.tradingFeeRate(), tradingFeeRate);
        assertEq(curve.migrationFeeRate(), migrationFeeRate);
        assertEq(curve.creationFee(), creationFee);
        assertEq(address(curve.swapRouter()), swapRouter);
        assertEq(curve.paused(), false);
        assertEq(curve.protocolFeeRecipient(), feeCollector);
        assertEq(curve.FEE_DENOMINATOR(), 100_00);
        assertEq(curve.MAX_FEE(), 10_00);
        assertEq(curve.TOTAL_SUPPLY(), 1_000_000_000 ether);
        assertEq(curve.INIT_VIRTUAL_TOKEN_RESERVE(), 1073000000 ether);
        assertEq(curve.INIT_REAL_TOKEN_RESERVE(), 793100000 ether);
        assertEq(curve.initVirtualEthReserve(), initVirtualEthReserve);
        assertEq(curve.migrationThreshold(), curve.CURVE_CONSTANT()/(curve.INIT_VIRTUAL_TOKEN_RESERVE() - curve.INIT_REAL_TOKEN_RESERVE()) - initVirtualEthReserve);
        assertEq(curve.CURVE_CONSTANT(), initVirtualEthReserve * curve.INIT_VIRTUAL_TOKEN_RESERVE());
    }

    function test_launch_token() public {
        TokenLaunchParam memory param = TokenLaunchParam({
            name: "Test Token 2",
            symbol: "TTK2",
            description: "Token launch for testing purpose",
            image: "image.jpg",
            twitterLink: "x.com/test2",
            telegramLink: "t.me/test2",
            website: "test2.com"
        });
        vm.startPrank(msg.sender);
        vm.recordLogs();
        uint256 beforeLaunchFeeCollectorBal = feeCollector.balance;
        uint256 beforeLaunchCreatorBal = msg.sender.balance;
        address token = curve.launchToken{value: creationFee}(param);
        uint256 afterLaunchFeeCollectorBal = feeCollector.balance;
        uint256 afterLaunchCreatorBal = msg.sender.balance;
        vm.stopPrank();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory transferEvent = logs[0];
        Vm.Log memory launchEvent = logs[1];
        Vm.Log memory priceUpdateEvent = logs[2];

        // ---- TRANSFER EVENT TOPICS & DATA
        assertEq(transferEvent.topics.length, 3);
        assertEq(transferEvent.topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(abi.decode(abi.encodePacked(transferEvent.topics[1]), (address)), address(0));
        assertEq(abi.decode(abi.encodePacked(transferEvent.topics[2]), (address)), address(curve));
        assertEq(abi.decode(transferEvent.data, (uint256)), curve.TOTAL_SUPPLY());
        
        // ---- LAUNCH EVENT TOPICS & DATA
        (
            address _token, string memory name, string memory symbol, 
            string memory description, string memory image, string memory twitterLink, 
            string memory telegramLink, string memory website, uint256 timestamp
        ) = abi.decode(launchEvent.data, (address,string,string,string,string,string,string,string,uint256));
        assertEq(launchEvent.topics.length, 2);
        assertEq(launchEvent.topics[0], keccak256("TokenLaunch(address,address,string,string,string,string,string,string,string,uint256)"));
        assertEq(abi.decode(abi.encodePacked(launchEvent.topics[1]), (address)), msg.sender);
        assertEq(_token, token);
        assertEq(name, param.name);
        assertEq(symbol, param.symbol);
        assertEq(description, param.description);
        assertEq(image, param.image);
        assertEq(twitterLink, param.twitterLink);
        assertEq(telegramLink, param.telegramLink);
        assertEq(website, param.website);
        assertEq(timestamp, block.timestamp);

        // ---- PRICE UPDATE EVENT TOPICS & DATA
        assertEq(priceUpdateEvent.topics.length, 3);
        assertEq(priceUpdateEvent.topics[0], keccak256("PriceUpdate(address,address,uint256,uint256,uint256)"));
        assertEq(abi.decode(abi.encodePacked(priceUpdateEvent.topics[1]), (address)), token);
        assertEq(abi.decode(abi.encodePacked(priceUpdateEvent.topics[2]), (address)), msg.sender);
        
        // ---- POOL VERIFICATION ----
        (
            RampToken token_, uint256 tokenReserve, uint256 virtualTokenReserve, uint256 ethReserve,
            uint256 virtualEthReserve, uint256 lastPrice, uint256 lastMcapInEth,
            uint256 lastTs, uint256 lastBlock, address creator, bool migrated
        ) = curve.tokenPool(token);
        assertEq(migrated, false);
        assertEq(virtualEthReserve, initVirtualEthReserve);
        assertEq(ethReserve, 0);
        assertEq(lastTs, block.timestamp);
        assertEq(lastBlock, block.number);
        assertEq(creator, msg.sender);
        assertEq(tokenReserve, curve.INIT_REAL_TOKEN_RESERVE());
        assertEq(virtualTokenReserve, curve.INIT_VIRTUAL_TOKEN_RESERVE());
        assertEq(lastPrice, initVirtualEthReserve.divWadDown(virtualTokenReserve));
        assertEq(lastMcapInEth, curve.TOTAL_SUPPLY().mulWadUp(lastPrice));


        // ---- TOKEN CHECKS ----
        assertEq(address(token_), token);
        assertEq(token_.curve(), address(curve));
        assertEq(token_.creator(), msg.sender);
        assertEq(token_.isApprovable(), false);

        // ---- CREATION FEE CHECKS ----
        assertEq(afterLaunchFeeCollectorBal - beforeLaunchFeeCollectorBal, creationFee);
        assertEq(beforeLaunchCreatorBal - afterLaunchCreatorBal, creationFee);
    }

    function test_swap_eth_for_tokens() public {
        vm.deal(trader, 100 ether);
        vm.startPrank(trader);
        vm.recordLogs();
        uint256 amountIn = 0.001 ether;
        uint256 fee = amountIn * tradingFeeRate / curve.FEE_DENOMINATOR();
        uint256 amountOutMin = curve.calcAmountOutFromEth(address(testToken), amountIn);
        (
            , uint256 beforeTokenReserve,, uint256 beforeEthReserve,
            uint256 beforeVirtualEthReserve,,,
            ,,,
        ) = curve.tokenPool(address(testToken));
        uint256 beforeFeeCollectorBal = feeCollector.balance;
        uint256 beforeTraderTokenBal = testToken.balanceOf(trader);
        uint256 beforeCurveBal = address(curve).balance;
        uint256 amountOut = curve.swapEthForTokens{value: amountIn}(address(testToken), amountIn, amountOutMin, block.timestamp + 1 minutes);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // ---- POOL VERIFICATION ----
        (
            , uint256 afterTokenReserve, uint256 virtualTokenReserve, uint256 afterEthReserve,
            uint256 afterVirtualEthReserve, uint256 lastPrice, uint256 lastMcapInEth,
            ,,, bool migrated
        ) = curve.tokenPool(address(testToken));
        assertEq(migrated, false);
        assertEq(afterVirtualEthReserve - beforeVirtualEthReserve, amountIn - fee);
        assertEq(afterEthReserve - beforeEthReserve, amountIn - fee);
        assertEq(beforeTokenReserve - afterTokenReserve, amountOut);
        assertEq(virtualTokenReserve, curve.CURVE_CONSTANT() / afterVirtualEthReserve);
        assertEq(lastPrice, afterVirtualEthReserve.divWadDown(virtualTokenReserve));
        assertEq(lastMcapInEth, curve.TOTAL_SUPPLY().mulWadUp(lastPrice));

        // ----- TRANSFER CHECKS (ETH & TOKEN TRANSFER) -----
        uint256 afterFeeCollectorBal = feeCollector.balance;
        uint256 afterTraderTokenBal = testToken.balanceOf(trader);
        uint256 afterCurveBal = address(curve).balance;
        assertEq(afterTraderTokenBal - beforeTraderTokenBal, amountOut);
        assertEq(afterFeeCollectorBal - beforeFeeCollectorBal, fee);
        assertEq(afterCurveBal - beforeCurveBal, amountIn - fee);

        // --- TRANSFER EVENT ---
        Vm.Log memory transferLog = logs[0];
        ( uint256 transferAmount ) = abi.decode(transferLog.data, (uint256));
        assertEq(transferLog.topics.length, 3);
        assertEq(transferLog.topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(abi.decode(abi.encodePacked(transferLog.topics[1]), (address)), address(curve));
        assertEq(abi.decode(abi.encodePacked(transferLog.topics[2]), (address)), trader);
        assertEq(transferAmount, amountOutMin);

        // --- PRICE UPDATE EVENT ---
        Vm.Log memory priceUpdateLog = logs[1];
        ( uint256 price, uint256 mcapEth, ) = abi.decode(priceUpdateLog.data, (uint256, uint256, uint256));
        assertEq(priceUpdateLog.topics.length, 3);
        assertEq(priceUpdateLog.topics[0], keccak256("PriceUpdate(address,address,uint256,uint256,uint256)"));
        assertEq(abi.decode(abi.encodePacked(priceUpdateLog.topics[1]), (address)), address(testToken));
        assertEq(abi.decode(abi.encodePacked(priceUpdateLog.topics[2]), (address)), trader);
        assertEq(price, lastPrice);
        assertEq(mcapEth, lastMcapInEth);

        // --- TRADE EVENT ---
        Vm.Log memory tradeLog = logs[2];
        ( 
            uint256 tradeAmountIn, uint256 tradeAmountOut, 
            uint256 tradeFee,,bool isBuy 
        ) = abi.decode(tradeLog.data, (uint256, uint256, uint256, uint256, bool));
        assertEq(tradeLog.topics.length, 3);
        assertEq(tradeLog.topics[0], keccak256("Trade(address,address,uint256,uint256,uint256,uint256,bool)"));
        assertEq(abi.decode(abi.encodePacked(tradeLog.topics[1]), (address)), trader);
        assertEq(abi.decode(abi.encodePacked(tradeLog.topics[2]), (address)), address(testToken));
        assertEq(tradeAmountIn, amountIn);
        assertEq(tradeAmountOut, amountOut);
        assertEq(tradeFee, fee);
        assertEq(isBuy, true);
    }

    function test_swap_tokens_for_eth() public {
        vm.deal(trader, 100 ether);
        vm.startPrank(trader);
        uint256 tokenAmountOut = curve.swapEthForTokens{value: 0.001 ether}(address(testToken), 0.001 ether, 0, block.timestamp + 1 minutes);
        uint256 amountIn = tokenAmountOut / 2;
        uint256 amountOutMin = curve.calcAmountOutFromToken(address(testToken), amountIn);
        uint256 fee = (amountOutMin * curve.FEE_DENOMINATOR() * curve.tradingFeeRate())/((curve.FEE_DENOMINATOR() - curve.tradingFeeRate()) * curve.FEE_DENOMINATOR());
        testToken.approve(address(curve), amountIn);
        vm.recordLogs();
        uint256 beforeFeeCollectorBal = feeCollector.balance;
        uint256 beforeTraderTokenBal = testToken.balanceOf(trader);
        uint256 beforeCurveBal = address(curve).balance;
        uint256 beforeCurveTokenBal = testToken.balanceOf(address(curve));
        (,uint256 beforeTokenReserve, uint256 beforeVirtualTokenReserve, uint256 beforeEthReserve,,,,,,,) = curve.tokenPool(address(testToken));
        uint256 amountOut = curve.swapTokensForEth(address(testToken), amountIn, amountOutMin, block.timestamp + 1 minutes);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // // ---- POOL VERIFICATION ----
        (
            , uint256 afterTokenReserve, uint256 afterVirtualTokenReserve, uint256 afterEthReserve,
            uint256 virtualEthReserve, uint256 lastPrice, uint256 lastMcapInEth,
            ,,, bool migrated
        ) = curve.tokenPool(address(testToken));
        assertEq(migrated, false);
        assertEq(virtualEthReserve, curve.CURVE_CONSTANT() / afterVirtualTokenReserve);
        assertEq(amountOut, amountOutMin);
        assertEq(beforeEthReserve - afterEthReserve, amountOut + fee);
        assertEq(afterTokenReserve - beforeTokenReserve, amountIn);
        assertEq(afterVirtualTokenReserve - beforeVirtualTokenReserve, amountIn);
        assertEq(lastPrice, virtualEthReserve.divWadDown(afterVirtualTokenReserve));
        assertEq(lastMcapInEth, curve.TOTAL_SUPPLY().mulWadUp(lastPrice));

        // ----- TRANSFER CHECKS (ETH & TOKEN TRANSFER) -----
        uint256 afterFeeCollectorBal = feeCollector.balance;
        uint256 afterTraderTokenBal = testToken.balanceOf(trader);
        uint256 afterCurveBal = address(curve).balance;
        uint256 afterCurveTokenBal = testToken.balanceOf(address(curve));
        assertEq(beforeTraderTokenBal - afterTraderTokenBal, amountIn);
        assertEq(afterFeeCollectorBal - beforeFeeCollectorBal, fee);
        assertEq(beforeCurveBal - afterCurveBal, amountOut + fee);
        assertEq(afterCurveTokenBal - beforeCurveTokenBal, amountIn);

        // ----- TRANSFER EVENT CHECKS -----
        Vm.Log memory transferLog = logs[0];
        ( uint256 transferAmount ) = abi.decode(transferLog.data, (uint256));
        assertEq(transferLog.topics.length, 3);
        assertEq(transferLog.topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(abi.decode(abi.encodePacked(transferLog.topics[1]), (address)), trader);
        assertEq(abi.decode(abi.encodePacked(transferLog.topics[2]), (address)), address(curve));
        assertEq(transferAmount, amountIn);

        // ----- PRICE UPDATE EVENT CHECKS ----
        Vm.Log memory priceUpdateLog = logs[1];
        ( uint256 price, uint256 mcapEth, ) = abi.decode(priceUpdateLog.data, (uint256, uint256, uint256));
        assertEq(priceUpdateLog.topics.length, 3);
        assertEq(priceUpdateLog.topics[0], keccak256("PriceUpdate(address,address,uint256,uint256,uint256)"));
        assertEq(abi.decode(abi.encodePacked(priceUpdateLog.topics[1]), (address)), address(testToken));
        assertEq(abi.decode(abi.encodePacked(priceUpdateLog.topics[2]), (address)), trader);
        assertEq(price, lastPrice);
        assertEq(mcapEth, lastMcapInEth);

        // ----- TRADE EVENT CHECKS -----
        Vm.Log memory tradeLog = logs[2];
        ( 
            uint256 tradeAmountIn, uint256 tradeAmountOut, 
            uint256 tradeFee,,bool isBuy 
        ) = abi.decode(tradeLog.data, (uint256, uint256, uint256, uint256, bool));
        assertEq(tradeLog.topics.length, 3);
        assertEq(tradeLog.topics[0], keccak256("Trade(address,address,uint256,uint256,uint256,uint256,bool)"));
        assertEq(abi.decode(abi.encodePacked(tradeLog.topics[1]), (address)), trader);
        assertEq(abi.decode(abi.encodePacked(tradeLog.topics[2]), (address)), address(testToken));
        assertEq(tradeAmountIn, amountIn);
        assertEq(tradeAmountOut, amountOutMin);
        assertEq(tradeFee, fee);
        assertEq(isBuy, false);
    }

    function test_migrate_liquidity() public {
        // Buy enough tokens to trigger liquidity migration
        vm.recordLogs();
        uint256 amountIn = 0.1 ether;
        uint256 fee = amountIn * tradingFeeRate / curve.FEE_DENOMINATOR();
        uint256 beforeFeeCollectorBal = feeCollector.balance;
        // Buy tokens enough to exceed threshold
        curve.swapEthForTokens{value: amountIn}(address(testToken), amountIn, 0, block.timestamp + 1 minutes);
        uint256 afterFeeCollectorBal = feeCollector.balance;
        ( 
            ,uint256 tokenReserve, uint256 virtualTokenReserve, uint256 ethReserve, 
            uint256 virtualEthReserve,,,,
            ,, bool migrated 
        ) = curve.tokenPool(address(testToken));
        IUniswapV2Router02 router = IUniswapV2Router02(swapRouter);
        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(uniswapV2Factory);
        address pairAddr = uniswapFactory.getPair(address(testToken), router.WETH());
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddr);
        ( uint112 ethReservePool, uint112 tokenReservePool, ) = pair.getReserves();
        uint256 expectedMigrationFee = (amountIn - fee) * migrationFeeRate / curve.FEE_DENOMINATOR();
        
        // Assertions
        assertEq(tokenReserve, 0);
        assertEq(virtualTokenReserve, 0);
        assertEq(ethReserve, 0);
        assertEq(virtualEthReserve, 0);
        assertEq(migrated, true);
        assertEq(testToken.isApprovable(), true);
        assertEq(afterFeeCollectorBal - beforeFeeCollectorBal, expectedMigrationFee + fee);
        assertEq(tokenReservePool, curve.TOTAL_SUPPLY() - curve.INIT_REAL_TOKEN_RESERVE());
        assertEq(ethReservePool, amountIn - fee - expectedMigrationFee);
        assertEq(testToken.balanceOf(address(curve)), 0);

        // Logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Vm.Log memory addLiqEvent = logs[11];
        Vm.Log memory migrateLiqEvent = logs[logs.length - 2];

        // Add Liquidity Event Tests [Mint Event]
        // ( uint amount0, uint amount1 ) = abi.decode(addLiqEvent.data, (uint, uint));
        // //console.log(amount0, amount1);
        // assertEq(addLiqEvent.topics.length, 2);
        // //assertEq(addLiqEvent.topics[0], keccak256("Mint(address,uint,uint)"));
        // assertEq(abi.decode(abi.encodePacked(addLiqEvent.topics[1]), (address)), address(0));
        
        // Migrate Liquidity Event Test
        ( uint256 ethAmount, uint256 tokenAmount, uint256 migFee, ) = abi.decode(migrateLiqEvent.data, (uint256, uint256, uint256, uint256));
        assertEq(migrateLiqEvent.topics.length, 3);
        assertEq(migrateLiqEvent.topics[0], keccak256("MigrateLiquidity(address,address,uint256,uint256,uint256,uint256)"));
        assertEq(abi.decode(abi.encodePacked(migrateLiqEvent.topics[1]), (address)), address(testToken));
        assertEq(abi.decode(abi.encodePacked(migrateLiqEvent.topics[2]), (address)), pairAddr);
        assertEq(ethAmount, ethReservePool);
        assertEq(tokenAmount, tokenReservePool);
        assertEq(migFee, expectedMigrationFee);
    }

    function test_swap_eth_for_tokens_on_router() public {
        vm.recordLogs();
        vm.startPrank(trader);
        vm.deal(trader, 10 ether);
        uint256 amountIn = 4 ether;
        //uint256 fee = amountIn * tradingFeeRate / curve.FEE_DENOMINATOR();

        // Buy tokens enough to exceed threshold and migrate liquidity to fraxswap
        curve.swapEthForTokens{value: amountIn}(address(testToken), amountIn, 0, block.timestamp + 1 minutes);

        IUniswapV2Router02 router = IUniswapV2Router02(swapRouter);
        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(uniswapV2Factory);
        address pairAddr = uniswapFactory.getPair(address(testToken), router.WETH());
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddr);
        uint256 beforeTokenBal = testToken.balanceOf(trader);
        ( uint112 beforeEthReserve, uint112 beforeTokenReserve, ) = pair.getReserves();
        // Buy Tokens on FraxSwap router
        uint256 amountOut = curve.swapEthForTokens{value: 1 ether}(address(testToken), 1 ether, 0, block.timestamp + 1 minutes);
        uint256 afterTokenBal = testToken.balanceOf(trader);
        ( uint112 afterEthReserve, uint112 afterTokenReserve, ) = pair.getReserves();
        vm.stopPrank();

        assertEq(beforeTokenReserve - afterTokenReserve, amountOut);
        assertEq(afterEthReserve > beforeEthReserve, true);
        assertEq(afterTokenBal - beforeTokenBal, amountOut);
    }

    function test_swap_tokens_for_eth_on_router() public {
        vm.recordLogs();
        vm.startPrank(trader);
        vm.deal(trader, 10 ether);
        uint256 amountIn = 4 ether;
        //uint256 fee = amountIn * tradingFeeRate / curve.FEE_DENOMINATOR();

        // Buy tokens enough to exceed threshold and migrate liquidity to fraxswap
        uint256 tokenAmount = curve.swapEthForTokens{value: amountIn}(address(testToken), amountIn, 0, block.timestamp + 1 minutes);

        IUniswapV2Router02 router = IUniswapV2Router02(swapRouter);
        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(uniswapV2Factory);
        address pairAddr = uniswapFactory.getPair(address(testToken), router.WETH());
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddr);
        uint256 beforeTokenBal = testToken.balanceOf(trader);
        ( uint112 beforeEthReserve, uint112 beforeTokenReserve, ) = pair.getReserves();
        // Sell Tokens on FraxSwap router
        testToken.approve(address(curve), tokenAmount/2);
        curve.swapTokensForEth(address(testToken), tokenAmount/2, 0, block.timestamp + 1 minutes);
        uint256 afterTokenBal = testToken.balanceOf(trader);
        ( uint112 afterEthReserve, uint112 afterTokenReserve, ) = pair.getReserves();
        vm.stopPrank();

        assertEq(afterTokenReserve - beforeTokenReserve, tokenAmount/2);
        assertEq(beforeEthReserve > afterEthReserve, true);
        assertEq(beforeTokenBal - afterTokenBal, tokenAmount/2);
    }

    function test_launch_token_with_zero_creation_fee() public {
        vm.prank(admin);
        curve.setCreationFee(0);
        TokenLaunchParam memory param = TokenLaunchParam({
            name: "Test Token 2",
            symbol: "TTK2",
            description: "Token launch for testing purpose",
            image: "image.jpg",
            twitterLink: "x.com/test2",
            telegramLink: "t.me/test2",
            website: "test2.com"
        });
        vm.prank(msg.sender);
        curve.launchToken(param);
    }

    function test_cannot_launch_token_with_insufficient_creation_fee() public {
        TokenLaunchParam memory param = TokenLaunchParam({
            name: "Test Token 2",
            symbol: "TTK2",
            description: "Token launch for testing purpose",
            image: "image.jpg",
            twitterLink: "x.com/test2",
            telegramLink: "t.me/test2",
            website: "test2.com"
        });
        vm.expectRevert(InsufficientPayment.selector);
        curve.launchToken(param);
    }

    function test_cannot_launch_token_when_paused() public {
        vm.prank(admin);
        curve.setPaused(true);
        TokenLaunchParam memory param = TokenLaunchParam({
            name: "Test Token 2",
            symbol: "TTK2",
            description: "Token launch for testing purpose",
            image: "image.jpg",
            twitterLink: "x.com/test2",
            telegramLink: "t.me/test2",
            website: "test2.com"
        });
        vm.expectRevert(Paused.selector);
        curve.launchToken(param);
    }

    function test_cannot_buy_tokens_when_paused() public {
        // Pause curve
        vm.prank(admin);
        curve.setPaused(true);
        // Buy test token
        vm.deal(trader, 100 ether);
        vm.startPrank(trader);
        vm.expectRevert(Paused.selector);
        curve.swapEthForTokens{value: 1 ether}(address(testToken), 1 ether, 0, block.timestamp + 1 minutes);
        vm.stopPrank();
    }

    function test_cannot_buy_tokens_with_insufficient_amount_out() public {
        vm.deal(trader, 100 ether);
        vm.startPrank(trader);
        uint256 amountIn = 1 ether;
        uint256 amountOutMin = curve.calcAmountOutFromEth(address(testToken), amountIn);
        amountOutMin = amountOutMin * 2;
        vm.expectRevert(InsufficientOutput.selector);
        curve.swapEthForTokens{value: amountIn}(address(testToken), amountIn, amountOutMin, block.timestamp + 1 minutes);
        vm.stopPrank();
    }

    function test_cannot_buy_token_with_insufficient_payment() public {
        vm.deal(trader, 100 ether);
        vm.startPrank(trader);
        uint256 amountIn = 1 ether;
        vm.expectRevert(InsufficientPayment.selector);
        curve.swapEthForTokens{value: 0.5 ether}(address(testToken), amountIn, 0, block.timestamp + 1 minutes);
        vm.stopPrank();
    }

    function test_cannot_buy_token_with_invalid_amount_in() public {
        vm.deal(trader, 100 ether);
        vm.startPrank(trader);
        uint256 amountIn = 0;
        vm.expectRevert(InvalidAmountIn.selector);
        curve.swapEthForTokens{value: 1 ether}(address(testToken), amountIn, 0, block.timestamp + 1 minutes);
        vm.stopPrank();
    }

    function test_calculate_amount_out_from_eth(uint256 amountIn) public view {
        // run fuzzy test to uncover potential overflow or underflow bug
        vm.assume(amountIn >= 1 ether && amountIn <= 1000 ether);
        curve.calcAmountOutFromEth(address(testToken), amountIn);
    }

    function test_calculate_amount_out_from_token(uint256 amountIn) public view {
        // run fuzzy test to uncover potential overflow or underflow bug
        vm.assume(amountIn >= 10000 ether && amountIn <= 10000000 ether);
        curve.calcAmountOutFromToken(address(testToken), amountIn);
    }
}

contract TestnetForkTest is MainnetForkTest {
    using FixedPointMathLib for uint256;

    function setRouterAndFactory() public override {
        swapRouter = 0x1689E7B1F10000AE47eBfE339a4f69dECd19F602;
        uniswapV2Factory = 0x7Ae58f10f7849cA6F5fB71b7f45CB416c9204b1e; 
    }
}