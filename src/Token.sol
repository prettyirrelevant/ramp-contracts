// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    address curve;

    constructor(
        string memory name,
        string memory symbol,
        address _curve
    ) ERC20(name, symbol) {
        curve = _curve;
    }

    function mintTo(address recipient, uint256 amount) external {
        require(msg.sender == curve, "not permitted");
        _mint(recipient, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        require(msg.sender == curve, "not permitted");
        _burn(from, amount);
    }
}
