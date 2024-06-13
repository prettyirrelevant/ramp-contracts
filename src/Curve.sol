// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Token} from "./Token.sol";
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol';

contract BondingCurveAMM {
    
    struct TokenLaunchParam {
        string name;
        string symbol;
        string description;
        string image;
        string twitterLink;
        string telegramLink;
        string website;
    }
    address admin;
    address protocolFeeRecipient;
    IUniswapV2Router01 swapRouter;
    uint256 protocolFeePercent; // decimals is 2 (i.e: 5% is 500)
    uint256 public reserveTarget;

    mapping(address => uint256) public tokenReserve;
    mapping(address => bool) public isLiquidityAdded;

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

    event Trade (
        address indexed trader,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee,
        uint256 timestamp,
        bool isBuy
    );

    event MigrateLiquidity (
        address indexed token,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 timestamp
    );

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not permitted");
        _;
    }

    constructor(uint256 target, address feeRecipient, uint256 feePercent, address router) {
        admin = msg.sender;
        reserveTarget = target;
        protocolFeeRecipient = feeRecipient;
        protocolFeePercent = feePercent;
        swapRouter = IUniswapV2Router01(router);
    }

    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : (supply - 1 )* (supply) * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = supply == 0 && amount == 1 ? 0 : (supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return summation * 1 ether / 16000;
    }


    function buyToken(address token, uint256 amount) public payable {
        // Todo: reroute the call to the fraxswap pool instead
        require(tokenReserve[token] < reserveTarget, "curve target reached");
        uint256 supply = Token(token).totalSupply();
        uint256 price = getPrice(supply, amount);
        uint256 protocolFee = price * protocolFeePercent / 100_00;
        require(msg.value >= price + protocolFee, "Insufficient payment for trade");
        tokenReserve[token] += price;
        (bool success, ) = protocolFeeRecipient.call{value: protocolFee}("");
        Token(token).mintTo(msg.sender, amount);
        require(success, "Unable to send protocol fee");
        emit Trade(
            msg.sender,
            token,
            msg.value,
            amount,
            protocolFee,
            block.timestamp,
            true
        );
    }

    function sellToken(address token, uint256 amount) public {
        // If the token has been migrated to fraxSwap, route the call to fraxSwap instead
        uint256 supply = Token(token).totalSupply();
        require(Token(token).balanceOf(msg.sender) >= amount, "insufficient balance to cover trade");
        uint256 price = getPrice(supply - amount, amount);
        uint256 protocolFee = price * protocolFeePercent / 100_00;
        tokenReserve[token] -= price;
        Token(token).burnFrom(msg.sender, amount);
        (bool success1, ) = msg.sender.call{value: price - protocolFee}("");
        (bool success2, ) = protocolFeeRecipient.call{value: protocolFee}("");
        require(success1 && success2, "Unable to send funds");
        emit Trade(
            msg.sender,
            token,
            amount,
            price - protocolFee,
            protocolFee,
            block.timestamp,
            false
        );
    }

    function launchToken(TokenLaunchParam memory param) public {
        Token token = new Token(param.name, param.symbol, address(this));
        emit TokenLaunch(
            msg.sender,
            address(token),
            param.name,
            param.symbol,
            param.description,
            param.image,
            param.twitterLink,
            param.telegramLink,
            param.website,
            block.timestamp
        );
    }

    function migrateLiqiudity(address _token) public onlyAdmin {
        require(tokenReserve[_token] >= reserveTarget, "reserve target not reached");
        Token token = Token(_token);
        uint256 ethAmount = tokenReserve[_token];
        uint256 supply = token.totalSupply();
        token.mintTo(address(this), supply);
        token.approve(address(swapRouter), supply);
        swapRouter.addLiquidityETH{value: ethAmount}(
            _token,
            supply,
            supply,
            ethAmount,
            address(0), // permanently lock the liquidity
            block.timestamp + 1 minutes
        );
        isLiquidityAdded[_token] = true;
        emit MigrateLiquidity(
            _token,
            ethAmount,
            supply,
            block.timestamp
        );
    }
}