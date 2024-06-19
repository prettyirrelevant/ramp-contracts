// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console, Vm} from "forge-std/Test.sol";
import { RampToken } from "../src/Token.sol";
import "../src/Curve.sol";

contract CurveTest is Test {

    RampBondingCurveAMM public curve;
    address public feeCollector;
    address public trader;
    address public admin;
    address swapRouter = address(0);
    uint256 tradingFeeRate = 100; // 1%
    uint256 migrationFeeRate = 700; // 1.5%
    uint256 creationFee = 10**15; // 0.001 ether
    uint256 initVirtualEthReserve = 6717 ether;
    

    function setUp() public {
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
            swapRouter
        );
    }


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
            name: "Test Token",
            symbol: "TTK",
            description: "Token launch for testing purpose",
            image: "image.jpg",
            twitterLink: "x.com/test",
            telegramLink: "t.me/test",
            website: "test.com"
        });
        vm.startPrank(msg.sender);
        vm.recordLogs();
        address token = curve.launchToken{value: creationFee}(param);
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
        assertEq(launchEvent.topics.length, 2);
        assertEq(launchEvent.topics[0], keccak256("TokenLaunch(address,address,string,string,string,string,string,string,string,uint256)"));
        assertEq(abi.decode(abi.encodePacked(launchEvent.topics[1]), (address)), msg.sender);
        // assertEq(name, param.name);
        // assertEq(symbol, param.symbol);
        // assertEq(description, param.description);
        // assertEq(image, param.image);
        // assertEq(twitterLink, param.twitterLink);
        // assertEq(telegramLink, param.telegramLink);
        // assertEq(website, param.website);
        // assertEq(timestamp, block.timestamp);

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

        // ---- TOKEN CHECKS ----
        assertEq(token_.curve(), address(curve));
        assertEq(token_.creator(), msg.sender);
        assertEq(token_.isApprovable(), false);
    }

    // function test_launch_token_with_zero_creation_fee() public {

    // }

    // function test_cannot_launch_token_when_paused() public {

    // }

    // function test_get_price(uint256 supply, uint256 amount) public view {
    //     // run fuzzy tests to uncover any potential overflow and underflow bug
    //     vm.assume(supply >= 1 ether && supply < 10_000_000_000_000 ether);
    //     vm.assume(amount >= 1 ether && amount < 1000000000 ether);
    //     curve.getPrice(supply, amount);
    // }

    

    // function test_only_curve_can_mint_and_burn() public {
    //     Token token = new Token("Test Token", "TTK", address(curve));
    //     vm.expectRevert("not permitted");
    //     token.mintTo(msg.sender, 100 ether);
    //     vm.prank(address(curve));
    //     token.mintTo(msg.sender, 100 ether);
    //     assertEq(token.balanceOf(msg.sender), 100 ether);
    //     assertEq(token.totalSupply(), 100 ether);
    //     vm.expectRevert("not permitted");
    //     token.burnFrom(msg.sender, 100 ether);
    //     vm.prank(address(curve));
    //     token.burnFrom(msg.sender, 100 ether);
    //     assertEq(token.balanceOf(msg.sender), 0);
    //     assertEq(token.totalSupply(), 0);
    // }

    // function test_buy_token() public {
    //     TokenLaunchParam memory param = TokenLaunchParam({
    //         name: "Test Token",
    //         symbol: "TTK",
    //         description: "Token launch for testing purpose",
    //         image: "image.jpg",
    //         twitterLink: "x.com/test",
    //         telegramLink: "t.me/test",
    //         website: "test.com"
    //     });
    //     vm.prank(msg.sender);
    //     vm.recordLogs();
    //     curve.launchToken(param);
    //     Vm.Log memory launchEvent = vm.getRecordedLogs()[0];
    //     ( address token,,,,,,,, ) = abi.decode(launchEvent.data, (address,string,string,string,string,string,string,string,uint256));
    //     uint256 amount = 10000 ether;
    //     uint256 priceWithFee = curve.getBuyPriceAfterFee(token, amount);
    //     uint256 buyPrice = curve.getBuyPrice(token, amount);
    //     vm.deal(trader, 100 ether);
    //     uint256 beforeBuyTraderBal = trader.balance;
    //     uint256 beforeBuyFeeCollectorBal = feeCollector.balance;
    //     uint256 beforeBuyCurveBal = address(curve).balance;
    //     uint256 beforeBuyTokenReserve = curve.tokenReserve(token);
    //     vm.prank(trader);
    //     curve.buyToken{value: priceWithFee}(token, amount);
    //     uint256 afterBuyTraderBal = trader.balance;
    //     uint256 afterBuyFeeCollectorBal = feeCollector.balance;
    //     uint256 afterBuyCurveBal = address(curve).balance;
    //     uint256 afterBuyTokenReserve = curve.tokenReserve(token);
    //     assertEq(Token(token).balanceOf(trader), amount);
    //     assertEq(Token(token).totalSupply(), amount);
    //     assertEq(beforeBuyTraderBal - afterBuyTraderBal, priceWithFee);
    //     assertEq(afterBuyFeeCollectorBal - beforeBuyFeeCollectorBal, priceWithFee - buyPrice);
    //     assertEq(afterBuyCurveBal - beforeBuyCurveBal, buyPrice);
    //     assertEq(afterBuyTokenReserve - beforeBuyTokenReserve, buyPrice);
    //     assertEq(curve.getPrice(0, Token(token).totalSupply()), curve.tokenReserve(token));
    // }

    // function test_sell_token() public pure {
    //     assertEq(false, true);
    // }
}