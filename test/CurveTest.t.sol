// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console, Vm} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";
import "../src/Curve.sol";

contract CurveTest is Test {

    event TokenLaunch (
        address indexed launcher,
        address token,
        string name,
        string symbol,
        string description,
        string image,
        string twitterLink,
        string telegramLink,
        string website,
        uint256 timestamp
    );

    BondingCurveAMM public curve;
    address public feeCollector;
    address public trader;
    address public admin;
    address swapRouter = address(0);
    uint256 protocolFee = 100; // 1%
    uint256 reserveTarget = 10 ether;

    function setUp() public {
        (feeCollector, ) = makeAddrAndKey("feeCollector");
        (trader, ) = makeAddrAndKey("trader");
        (admin, ) = makeAddrAndKey("admin");
        vm.prank(admin);
        curve = new BondingCurveAMM(10 ether, feeCollector, protocolFee, swapRouter);
    }


    function test_contract_variables() public view {
        assertEq(curve.admin(), admin);
        assertEq(curve.protocolFeeRecipient(), feeCollector);
        assertEq(address(curve.swapRouter()), swapRouter);
        assertEq(curve.reserveTarget(), reserveTarget);
        assertEq(curve.protocolFeePercent(), protocolFee);
    }

    function test_get_price(uint256 supply, uint256 amount) public view {
        // run fuzzy tests to uncover any potential overflow and underflow bug
        vm.assume(supply >= 1 ether && supply < 10_000_000_000_000 ether);
        vm.assume(amount >= 1 ether && amount < 1000000000 ether);
        curve.getPrice(supply, amount);
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
        curve.launchToken(param);
        Vm.Log memory launchEvent = vm.getRecordedLogs()[0];
        (
            address token, string memory name, string memory symbol, 
            string memory description, string memory image, string memory twitterLink, 
            string memory telegramLink, string memory website, uint256 timestamp
        ) = abi.decode(launchEvent.data, (address,string,string,string,string,string,string,string,uint256));
        assertEq(launchEvent.topics.length, 2);
        assertEq(launchEvent.topics[0], keccak256("TokenLaunch(address,address,string,string,string,string,string,string,string,uint256)"));
        assertEq(abi.decode(abi.encodePacked(launchEvent.topics[1]), (address)), msg.sender);
        assertEq(name, param.name);
        assertEq(symbol, param.symbol);
        assertEq(description, param.description);
        assertEq(image, param.image);
        assertEq(twitterLink, param.twitterLink);
        assertEq(telegramLink, param.telegramLink);
        assertEq(website, param.website);
        assertEq(timestamp, block.timestamp);
        assertEq(curve.isLiquidityAdded(token), false);
        assertEq(curve.tokenReserve(token), 0);
        assertEq(Token(token).decimals(), 18);
        assertEq(Token(token).name(), param.name);
        assertEq(Token(token).totalSupply(), 0);
        assertEq(Token(token).symbol(), param.symbol);
        assertEq(Token(token).curve(), address(curve));
        vm.stopPrank();
    }

    function test_only_curve_can_mint_and_burn() public {
        Token token = new Token("Test Token", "TTK", address(curve));
        vm.expectRevert("not permitted");
        token.mintTo(msg.sender, 100 ether);
        vm.prank(address(curve));
        token.mintTo(msg.sender, 100 ether);
        assertEq(token.balanceOf(msg.sender), 100 ether);
        assertEq(token.totalSupply(), 100 ether);
        vm.expectRevert("not permitted");
        token.burnFrom(msg.sender, 100 ether);
        vm.prank(address(curve));
        token.burnFrom(msg.sender, 100 ether);
        assertEq(token.balanceOf(msg.sender), 0);
        assertEq(token.totalSupply(), 0);
    }

    function test_buy_token() public {
        TokenLaunchParam memory param = TokenLaunchParam({
            name: "Test Token",
            symbol: "TTK",
            description: "Token launch for testing purpose",
            image: "image.jpg",
            twitterLink: "x.com/test",
            telegramLink: "t.me/test",
            website: "test.com"
        });
        vm.prank(msg.sender);
        vm.recordLogs();
        curve.launchToken(param);
        Vm.Log memory launchEvent = vm.getRecordedLogs()[0];
        ( address token,,,,,,,, ) = abi.decode(launchEvent.data, (address,string,string,string,string,string,string,string,uint256));
        uint256 amount = 10000 ether;
        uint256 priceWithFee = curve.getBuyPriceAfterFee(token, amount);
        uint256 buyPrice = curve.getBuyPrice(token, amount);
        vm.deal(trader, 100 ether);
        uint256 beforeBuyTraderBal = trader.balance;
        uint256 beforeBuyFeeCollectorBal = feeCollector.balance;
        uint256 beforeBuyCurveBal = address(curve).balance;
        uint256 beforeBuyTokenReserve = curve.tokenReserve(token);
        vm.prank(trader);
        curve.buyToken{value: priceWithFee}(token, amount);
        uint256 afterBuyTraderBal = trader.balance;
        uint256 afterBuyFeeCollectorBal = feeCollector.balance;
        uint256 afterBuyCurveBal = address(curve).balance;
        uint256 afterBuyTokenReserve = curve.tokenReserve(token);
        assertEq(Token(token).balanceOf(trader), amount);
        assertEq(Token(token).totalSupply(), amount);
        assertEq(beforeBuyTraderBal - afterBuyTraderBal, priceWithFee);
        assertEq(afterBuyFeeCollectorBal - beforeBuyFeeCollectorBal, priceWithFee - buyPrice);
        assertEq(afterBuyCurveBal - beforeBuyCurveBal, buyPrice);
        assertEq(afterBuyTokenReserve - beforeBuyTokenReserve, buyPrice);
        assertEq(curve.getPrice(0, Token(token).totalSupply()), curve.tokenReserve(token));
    }

    function test_sell_token() public pure {
        assertEq(false, true);
    }
}