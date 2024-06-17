// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Token } from "./Token.sol";
import {console} from "forge-std/Test.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

error NotPermitted();
error Paused();

contract RampBondingCurveAMM is ReentrancyGuard {
    struct TokenLaunchParam {
        string name;
        string symbol;
        string description;
        string image;
        string twitterLink;
        string telegramLink;
        string website;
    }

    struct Pool {
        Token token;
        uint256 tokenReserve;
        uint256 virtualTokenReserve;
        uint256 ethReserve;
        uint256 virtualEthReserve;
        uint256 lastPrice;
        uint256 lastMcapInEth;
        uint256 lastTimestamp;
        uint256 lastBlock;
        address creator;
        bool migrated;
    }

    uint256 public constant FEE_DENOMINATOR = 100_00;
    uint256 public constant MAX_FEE = 10_00; // 10%

    uint256 public constant INIT_VIRTUAL_TOKEN_RESERVE = 1073000000 ether;
    uint256 public constant INIT_REAL_TOKEN_RESERVE = 793100000 ether;
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint256 public initVirtualEthReserve;
    uint256 public migrationThreshold;
    uint256 public CURVE_CONSTANT;

    address public admin;
    address payable public protocolFeeRecipient;
    IUniswapV2Router01 public swapRouter;
    uint256 public creationFee;
    uint256 public tradingFee;
    uint256 public migrationFee;
    bool public paused;

    //mapping(address => bool) public isLiquidityAdded;
    mapping(address => Pool) public tokenPool;

    event TokenLaunch(
        address indexed creator,
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
        uint256 currentPrice,
        uint256 timestamp,
        bool isBuy
    );

    event MigrateLiquidity(address indexed token, uint256 ethAmount, uint256 tokenAmount, uint256 timestamp);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotPermitted();
        _;
    }

    modifier onlyUnPaused() {
        if (paused) revert Paused();
        _;
    }

    constructor(
        uint256 _tradingFee,
        uint256 _migrationFee,
        uint256 _creationFee,
        uint256 _initVirtualEthReserve,
        address feeRecipient,
        address router
    ) {
        admin = msg.sender;
        tradingFee = _tradingFee;
        migrationFee = _migrationFee;
        creationFee = _creationFee;
        swapRouter = IUniswapV2Router01(router);
        paused_ = false;
        protocolFeeRecipient = feeRecipient;
        initVirtualEthReserve = _initVirtualEthReserve;
        CURVE_CONSTANT = initVirtualEthReserve * INIT_VIRTUAL_TOKEN_RESERVE;
        migrationThreshold = CURVE_CONSTANT / (INIT_VIRTUAL_TOKEN_RESERVE - INIT_REAL_TOKEN_RESERVE) - initVirtualEthReserve;
    }

    function launchToken(TokenLaunchParam memory param) external {
        Token token = new Token(param.name, param.symbol, address(this), msg.sender, TOTAL_SUPPLY);
        Pool storage pool = tokenPool[address(token)];
        pool.token = token;
        pool.tokenReserve = INIT_REAL_TOKEN_RESERVE;
        pool.virtualTokenReserve = INIT_VIRTUAL_TOKEN_RESERVE;
        pool.ethReserve = 0;
        pool.virtualEthReserve = initVirtualEthReserve;
        
        tokenReserve[address(token)] = 0;
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

    function getPrice(uint256 supply, uint256 amount) public view returns (uint256) {
        uint256 scaledSupply = supply / 1 ether;
        uint256 scaledAmount = amount / 1 ether;

        uint256 sum1 = scaledSupply == 0 ? 0 : (scaledSupply - 1) * (scaledSupply) * (2 * (scaledSupply - 1) + 1) / 6;
        uint256 sum2 = (scaledSupply + scaledAmount - 1) * (scaledSupply + scaledAmount) * (2 * (scaledSupply + scaledAmount - 1) + 1) / 6;

        uint256 summation = sum2 - sum1;

        return summation * 1 ether / 9_600_000_000_000;
    }

    function getBuyPrice(address _token, uint256 amount) public view returns (uint256) {
        return getPrice(Token(_token).totalSupply(), amount);
    }

    function getSellPrice(address _token, uint256 amount) public view returns (uint256) {
        return getPrice(Token(_token).totalSupply() - amount, amount);
    }

    function getBuyPriceAfterFee(address _token, uint256 amount) public view returns (uint256) {
        uint256 price = getBuyPrice(_token, amount);
        uint256 fees = price * protocolFeePercent/100_00;
        return price + fees;
    }

    function getSellPriceAfterFee(address _token, uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(_token, amount);
        uint256 fees = price * protocolFeePercent/100_00;
        return price - fees;
    }

    function swapETHForToken(address token, uint256 amountIn, uint256 amountOutMin, address to) internal returns (uint256, uint256) {
        require(msg.value >= amountIn, "insufficient eth provided for swap");
        uint256 protocolFee = (amountIn * protocolFeePercent) / 100_00;
        address[] memory path = new address[](2);
        path[0] = swapRouter.WETH();
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
        path[0] = token;
        path[1] = swapRouter.WETH();
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
        require(amount != 0, 'invalid amount');
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
            (bool success, ) = protocolFeeRecipient.call{ value: fee }("");
            require(success, "unable to transfer fee");
            tokenReserve[token] += price;
            Token(token).mintTo(msg.sender, amount);
        }
        emit Trade(msg.sender, token, msg.value, amount, fee, block.timestamp, true);
    }

    function sellToken(address _token, uint256 amountIn, uint256 amountOutMin) public {
        require(amountIn != 0, 'invalid amount');
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
