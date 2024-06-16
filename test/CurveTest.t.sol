// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";
import {BondingCurveAMM} from "../src/Curve.sol";

contract CurveTest is Test {

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
        vm.assume(supply >= 1 ether && supply < 10_000_000_000_000 ether);
        vm.assume(amount < 1000000000 ether);
        uint256 price = curve.getPrice(supply, amount);
        console.log(amount, supply, price);
    }
}