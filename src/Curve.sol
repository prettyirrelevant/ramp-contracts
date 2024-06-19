// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { RampToken } from "./Token.sol";
import { console } from "forge-std/Test.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

error NotPermitted();
error Paused();
error InsufficientPayment();
error InvalidAmountIn();
error InsufficientOutput();
error DeadlineExceeded();
error InvalidToken();

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
    RampToken token;
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

contract RampBondingCurveAMM is ReentrancyGuard {
    using FixedPointMathLib for uint256;

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
    uint256 public tradingFeeRate;
    uint256 public migrationFeeRate;
    bool public paused;

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
    event PriceUpdate(
        address indexed token,
        address indexed trader,
        uint256 price,
        uint256 mcapEth,
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

    event MigrateLiquidity(address indexed token, uint256 ethAmount, uint256 tokenAmount, uint256 fee, uint256 timestamp);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotPermitted();
        _;
    }

    modifier onlyUnPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert DeadlineExceeded();
        _;
    }

    constructor(
        uint256 _tradingFeeRate,
        uint256 _migrationFeeRate,
        uint256 _creationFee,
        uint256 _initVirtualEthReserve,
        address feeRecipient,
        address router
    ) {
        admin = msg.sender;
        tradingFeeRate = _tradingFeeRate;
        migrationFeeRate = _migrationFeeRate;
        creationFee = _creationFee;
        swapRouter = IUniswapV2Router01(router);
        paused = false;
        protocolFeeRecipient = payable(feeRecipient);
        initVirtualEthReserve = _initVirtualEthReserve;
        CURVE_CONSTANT = initVirtualEthReserve * INIT_VIRTUAL_TOKEN_RESERVE;
        migrationThreshold = CURVE_CONSTANT / (INIT_VIRTUAL_TOKEN_RESERVE - INIT_REAL_TOKEN_RESERVE) - initVirtualEthReserve;
    }

    function launchToken(TokenLaunchParam memory param) external payable onlyUnPaused returns (address) {
        if (msg.value < creationFee) revert InsufficientPayment();
        if (creationFee > 0) SafeTransferLib.safeTransferETH(protocolFeeRecipient, creationFee);
        RampToken token = new RampToken(param.name, param.symbol, address(this), msg.sender, TOTAL_SUPPLY);
        Pool storage pool = tokenPool[address(token)];
        pool.token = token;
        pool.tokenReserve = INIT_REAL_TOKEN_RESERVE;
        pool.virtualTokenReserve = INIT_VIRTUAL_TOKEN_RESERVE;
        pool.ethReserve = 0;
        pool.virtualEthReserve = initVirtualEthReserve;
        pool.lastPrice = initVirtualEthReserve.divWadDown(INIT_VIRTUAL_TOKEN_RESERVE);
        pool.lastMcapInEth = TOTAL_SUPPLY.mulWadUp(pool.lastPrice);
        pool.lastTimestamp = block.timestamp;
        pool.lastBlock = block.number;
        pool.creator = msg.sender;
        pool.migrated = false;

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
        emit PriceUpdate(
            address(token), 
            msg.sender, 
            pool.lastPrice, 
            pool.lastMcapInEth, 
            block.timestamp
        );
        return address(token);
    }

    function swapEthForTokens(address token, uint256 amountIn, uint256 amountOutMin, uint256 deadline) 
        external 
        payable 
        nonReentrant 
        onlyUnPaused 
        checkDeadline(deadline) 
        returns (uint256 amountOut) 
    {
        uint256 fee = amountIn * tradingFeeRate / FEE_DENOMINATOR;
        amountIn -= fee;
        if (msg.value >= amountIn) revert InsufficientPayment();
        SafeTransferLib.safeTransferETH(protocolFeeRecipient, fee);
        if (tokenPool[token].migrated) {
            // route call to swapRouter
        } else {
            if (tokenPool[token].creator == address(0)) revert InvalidToken();
            uint256 newVirtualEthReserve = tokenPool[token].virtualEthReserve + amountIn;
            uint256 newVirtualTokenReserve = CURVE_CONSTANT / newVirtualEthReserve;
            amountOut = tokenPool[token].virtualTokenReserve - newVirtualTokenReserve;

            if (amountOut > tokenPool[token].tokenReserve) {
                amountOut = tokenPool[token].tokenReserve;
            }
            if (amountOut < amountOutMin) revert InsufficientOutput();

            tokenPool[token].virtualEthReserve = newVirtualEthReserve;
            tokenPool[token].virtualTokenReserve = newVirtualTokenReserve;

            tokenPool[token].lastPrice = newVirtualEthReserve.divWadDown(newVirtualTokenReserve);
            tokenPool[token].lastMcapInEth = TOTAL_SUPPLY.mulWadUp(tokenPool[token].lastPrice);
            tokenPool[token].lastTimestamp = block.timestamp;
            tokenPool[token].lastBlock = block.number;
            tokenPool[token].ethReserve += amountIn;
            tokenPool[token].tokenReserve -= amountOut;
            SafeTransferLib.safeTransfer(ERC20(token), msg.sender, amountOut);
            emit PriceUpdate(token, msg.sender, tokenPool[token].lastPrice, tokenPool[token].lastMcapInEth, block.timestamp);

            if (tokenPool[token].ethReserve >= migrationThreshold) {
                _migrateLiquidity(token);
            }
        }
        emit Trade(msg.sender, token, amountIn, amountOut, fee, block.timestamp, true);
    }

    function swapTokensForEth(address token, uint256 amountIn, uint256 amountOutMin, uint256 deadline)
        external
        nonReentrant
        onlyUnPaused
        checkDeadline(deadline)
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InvalidAmountIn();
        if (tokenPool[token].migrated) {
            // route call to swapRouter
        } else {
            if (tokenPool[token].creator == address(0)) revert InvalidToken();
            SafeTransferLib.safeTransferFrom(ERC20(token), msg.sender, address(this), amountIn);
        
            uint256 newVirtualTokenReserve = tokenPool[token].virtualTokenReserve + amountIn;
            uint256 newVirtualEthReserve = CURVE_CONSTANT / newVirtualTokenReserve;
            amountOut = tokenPool[token].virtualEthReserve - newVirtualEthReserve;

            tokenPool[token].virtualTokenReserve = newVirtualTokenReserve;
            tokenPool[token].virtualEthReserve = newVirtualEthReserve;
            tokenPool[token].lastPrice = newVirtualEthReserve.divWadDown(newVirtualTokenReserve);
            tokenPool[token].lastMcapInEth = TOTAL_SUPPLY.mulWadUp(tokenPool[token].lastPrice);
            tokenPool[token].lastTimestamp = block.timestamp;
            tokenPool[token].lastBlock = block.number;
            tokenPool[token].tokenReserve += amountIn;
            tokenPool[token].ethReserve -= amountOut;

            uint256 fee = amountOut * tradingFeeRate / FEE_DENOMINATOR;
            amountOut -= fee;

            if (amountOut < amountOutMin) revert InsufficientOutput();
            SafeTransferLib.safeTransferETH(protocolFeeRecipient, fee);
            SafeTransferLib.safeTransferETH(msg.sender, amountOut);
            emit Trade(msg.sender, token, amountIn, amountOut, fee, block.timestamp, false);
        }
    }

    function _migrateLiquidity(address token) private {
        if (tokenPool[token].creator == address(0)) revert InvalidToken();
        tokenPool[token].lastTimestamp = block.timestamp;
        tokenPool[token].lastBlock = block.number;

        uint256 fee = tokenPool[token].ethReserve * migrationFeeRate / FEE_DENOMINATOR;
        SafeTransferLib.safeTransferETH(protocolFeeRecipient, fee);
        uint256 ethAmount = tokenPool[token].ethReserve - fee;
        uint256 tokenAmount = TOTAL_SUPPLY - INIT_REAL_TOKEN_RESERVE;

        bool success = RampToken(token).approve(address(swapRouter), tokenAmount);
        require(success, "token approval failed");
        swapRouter.addLiquidityETH{ value: ethAmount }(
            token,
            tokenAmount,
            tokenAmount,
            ethAmount,
            address(0), // permanently lock the liquidity
            block.timestamp + 1 minutes
        );
        tokenPool[token].migrated = true;
        tokenPool[token].virtualEthReserve = 0;
        tokenPool[token].virtualTokenReserve = 0;
        tokenPool[token].ethReserve = 0;
        tokenPool[token].tokenReserve = 0;
        emit MigrateLiquidity(token, ethAmount, tokenAmount, fee, block.timestamp);
    }

    function calcAmountOutFromToken(address token, uint256 amountIn) external view returns (uint256 amountOut) {
        if (amountIn == 0) revert InvalidAmountIn();

        uint256 newVirtualTokenReserve = tokenPool[token].virtualTokenReserve + amountIn;
        uint256 newVirtualEthReserve = CURVE_CONSTANT / newVirtualTokenReserve;
        amountOut = tokenPool[token].virtualEthReserve - newVirtualEthReserve;

        uint256 fee = amountOut * tradingFeeRate / FEE_DENOMINATOR;
        amountOut -= fee;
    }

    function calcAmountOutFromEth(address token, uint256 amountIn) external view returns (uint256 amountOut) {
        if (amountIn == 0) revert InvalidAmountIn();

        uint256 fee = amountIn * tradingFeeRate / FEE_DENOMINATOR;
        amountIn -= fee;

        uint256 newVirtualEthReserve = tokenPool[token].virtualEthReserve + amountIn;
        uint256 newVirtualTokenReserve = CURVE_CONSTANT / newVirtualEthReserve;
        amountOut = tokenPool[token].virtualTokenReserve - newVirtualTokenReserve;

        if (amountOut > tokenPool[token].tokenReserve) {
            amountOut = tokenPool[token].tokenReserve;
        }
    }



    function _swapETHForTokenOnRouter(address token, uint256 amountIn, uint256 amountOutMin, address to) private returns (uint256, uint256) {
        if (msg.value < amountIn) revert InsufficientPayment();
        uint256 fee = (amountIn * tradingFeeRate) / FEE_DENOMINATOR;
        address[] memory path = new address[](2);
        path[0] = swapRouter.WETH();
        path[1] = token;
        uint[] memory amounts = swapRouter.swapExactETHForTokens{value: amountIn - fee}(
            amountOutMin,
            path,
            to,
            block.timestamp + 1 minutes
        );
        uint amountOut = amounts[amounts.length - 1];
        SafeTransferLib.safeTransferETH(protocolFeeRecipient, fee);
        return (amountOut, fee);
    }

    function _swapTokenForETHOnRouter(address token, uint256 amountIn, uint256 amountOutMin, address to) private returns (uint256, uint256) {
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
        uint256 fee = (amountOut * tradingFeeRate) / FEE_DENOMINATOR;
        SafeTransferLib.safeTransferETH(protocolFeeRecipient, fee);
        SafeTransferLib.safeTransferETH(to, amountOut - fee);
        return (amountOut - fee, fee);
    }

    // function buyToken(address token, uint256 amount) public payable {
    //     require(amount != 0, 'invalid amount');
    //     uint256 fee = 0;
    //     uint256 amountOut = 0;
    //     if (isLiquidityAdded[token]) {
    //         (fee, amountOut) = swapETHForToken(token, msg.value, amount, msg.sender);
    //     } else {
    //         require(tokenReserve[token] < reserveTarget, "curve target reached");
    //         uint256 supply = Token(token).totalSupply();
    //         uint256 price = getPrice(supply, amount);
    //         fee = (price * protocolFeePercent) / 100_00;
    //         amountOut = amount;
    //         require(msg.value >= price + fee, "Insufficient payment for trade");
    //         (bool success, ) = protocolFeeRecipient.call{ value: fee }("");
    //         require(success, "unable to transfer fee");
    //         tokenReserve[token] += price;
    //         Token(token).mintTo(msg.sender, amount);
    //     }
    //     emit Trade(msg.sender, token, msg.value, amount, fee, block.timestamp, true);
    // }

    // function sellToken(address _token, uint256 amountIn, uint256 amountOutMin) public {
    //     require(amountIn != 0, 'invalid amount');
    //     uint256 fee = 0;
    //     uint256 amountOut = 0;
    //     Token token = Token(_token);
    //     if (isLiquidityAdded[_token]) {
    //         bool success1 = token.transferFrom(msg.sender, address(this), amountIn);
    //         bool success2 = token.approve(address(swapRouter), amountIn);
    //         require(success1 && success2, "failed to move tokens");
    //         (fee, amountOut) = swapTokenForETH(_token, amountIn, amountOutMin, msg.sender);
    //     } else {
    //         uint256 supply = token.totalSupply();
    //         require(token.balanceOf(msg.sender) >= amountIn, "insufficient balance to cover trade");
    //         uint256 price = getPrice(supply - amountIn, amountIn);
    //         uint256 protocolFee = (price * protocolFeePercent) / 100_00;
    //         tokenReserve[_token] -= price;
    //         Token(token).burnFrom(msg.sender, amountIn);
    //         (bool success1, ) = msg.sender.call{ value: price - protocolFee }("");
    //         (bool success2, ) = protocolFeeRecipient.call{ value: protocolFee }("");
    //         require(success1 && success2, "Unable to send funds");
    //         fee = protocolFee;
    //         amountOut = price - fee;
    //     }
    //     emit Trade(msg.sender, _token, amountIn, amountOut, fee, block.timestamp, false);
    // }

    // function migrateLiqiudity(address _token) public onlyAdmin {
    //     require(tokenReserve[_token] >= reserveTarget, "reserve target not reached");
    //     Token token = Token(_token);
    //     uint256 ethAmount = tokenReserve[_token];
    //     uint256 supply = token.totalSupply();
    //     token.mintTo(address(this), supply);
    //     bool success = token.approve(address(swapRouter), supply);
    //     require(success, "token approval failed");
    //     swapRouter.addLiquidityETH{ value: ethAmount }(
    //         _token,
    //         supply,
    //         supply,
    //         ethAmount,
    //         address(0), // permanently lock the liquidity
    //         block.timestamp + 1 minutes
    //     );
    //     isLiquidityAdded[_token] = true;
    //     emit MigrateLiquidity(_token, ethAmount, supply, block.timestamp);
    // }
}
