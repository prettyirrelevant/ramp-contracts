// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Token } from "./Token.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

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

    event TokenLaunch(
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

    event Trade(
        address indexed trader,
        address indexed token,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee,
        uint256 timestamp,
        bool isBuy
    );

    event MigrateLiquidity(address indexed token, uint256 ethAmount, uint256 tokenAmount, uint256 timestamp);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not permitted");
        _;
    }

    constructor(
        uint256 target,
        address feeRecipient,
        uint256 feePercent,
        address router
    ) {
        admin = msg.sender;
        reserveTarget = target;
        protocolFeeRecipient = feeRecipient;
        protocolFeePercent = feePercent;
        swapRouter = IUniswapV2Router01(router);
    }

    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : ((supply - 1) * (supply) * (2 * (supply - 1) + 1)) / 6;
        uint256 sum2 = supply == 0 && amount == 1
            ? 0
            : ((supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1)) / 6;
        uint256 summation = sum2 - sum1;
        return (summation * 1 ether) / 16000;
    }

    function swapETHForToken(address token, uint256 amountIn, uint256 amountOutMin, address to) internal returns (uint256, uint256) {
        require(msg.value >= amountIn, "insufficient eth provided for swap");
        uint256 protocolFee = (amountIn * protocolFeePercent) / 100_00;
        address[] memory path = new address[](2);
        path[0] = address(0);
        path[1] = token;
        uint[] memory amounts = swapRouter.swapExactETHForTokens{value: amountIn - protocolFee}(
            amountOutMin,
            path,
            to,
            block.timestamp + 1 minutes
        );
        uint amountOut = amounts[amounts.length - 1];
        (bool success, ) = protocolFeeRecipient.call{ value: protocolFee }("");
        require(success, "Unable to send protocol fee");
        return (protocolFee, amountOut);
    }

    function swapTokenForETH(address token, uint256 amountIn, uint256 amountOutMin, address to) internal returns (uint256, uint256) {
        address[] memory path = new address[](2);
        path[0] = address(0);
        path[1] = token;
        uint[] memory amounts = swapRouter.swapExactTokensForETH(
            amountIn, 
            amountOutMin, 
            path,
            address(this), 
            block.timestamp + 1 minutes
        );
        uint amountOut = amounts[amounts.length - 1];
        uint256 protocolFee = (amountOut * protocolFeePercent) / 100_00;
        (bool success1,) = to.call{ value: amountOut - protocolFee}("");
        (bool success2, ) = protocolFeeRecipient.call{ value: protocolFee }("");
        require(success1 && success2, "unable to send funds");
        return (protocolFee, amountOut - protocolFee);
    }

    function buyToken(address token, uint256 amount) public payable {
        uint256 fee = 0;
        uint256 amountOut = 0;
        if (isLiquidityAdded[token]) {
            (fee, amountOut) = swapETHForToken(token, msg.value, amount, msg.sender);
        } else {
            require(tokenReserve[token] < reserveTarget, "curve target reached");
            uint256 supply = Token(token).totalSupply();
            uint256 price = getPrice(supply, amount);
            fee = (price * protocolFeePercent) / 100_00;
            amountOut = amount;
            require(msg.value >= price + fee, "Insufficient payment for trade");
            tokenReserve[token] += price;
            Token(token).mintTo(msg.sender, amount);
        }
        emit Trade(msg.sender, token, msg.value, amount, fee, block.timestamp, true);
    }

    function sellToken(address _token, uint256 amountIn, uint256 amountOutMin) public {
        uint256 fee = 0;
        uint256 amountOut = 0;
        Token token = Token(_token);
        if (isLiquidityAdded[_token]) {
            bool success1 = token.transferFrom(msg.sender, address(this), amountIn);
            bool success2 = token.approve(address(swapRouter), amountIn);
            require(success1 && success2, "failed to move tokens");
            (fee, amountOut) = swapTokenForETH(_token, amountIn, amountOutMin, msg.sender);
        } else {
            uint256 supply = token.totalSupply();
            require(token.balanceOf(msg.sender) >= amountIn, "insufficient balance to cover trade");
            uint256 price = getPrice(supply - amountIn, amountIn);
            uint256 protocolFee = (price * protocolFeePercent) / 100_00;
            tokenReserve[_token] -= price;
            Token(token).burnFrom(msg.sender, amountIn);
            (bool success1, ) = msg.sender.call{ value: price - protocolFee }("");
            (bool success2, ) = protocolFeeRecipient.call{ value: protocolFee }("");
            require(success1 && success2, "Unable to send funds");
            fee = protocolFee;
            amountOut = price - fee;
        }
        emit Trade(msg.sender, _token, amountIn, amountOut, fee, block.timestamp, false);
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
        bool success = token.approve(address(swapRouter), supply);
        require(success, "token approval failed");
        swapRouter.addLiquidityETH{ value: ethAmount }(
            _token,
            supply,
            supply,
            ethAmount,
            address(0), // permanently lock the liquidity
            block.timestamp + 1 minutes
        );
        isLiquidityAdded[_token] = true;
        emit MigrateLiquidity(_token, ethAmount, supply, block.timestamp);
    }
}
