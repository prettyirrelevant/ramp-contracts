// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

error NotApprovable();
error NotRampBondingCurve();

contract RampToken is ERC20Permit {
    
    address public immutable curve;
    address public immutable creator;

    /// @notice Prevent trading on AMMs until liquidity migration
    bool public isApprovable = false;
    bool public isLiquidityMigrated = false;

    constructor(
        string memory name,
        string memory symbol,
        address _curve,
        address _creator,
        uint256 _supply,
    ) ERC20(name, symbol) {
        curve = _curve;
        creator = _creator;
        _mint(msg.sender, _supply);
    }

    function mintTo(address recipient, uint256 amount) external {
        if (msg.sender != curve) revert NotBondingCurve();
        _mint(recipient, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        if (msg.sender != curve) revert NotRampBondingCurve();
        _burn(from, amount);
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        if (!isApprovable) revert NotApprovable();
        return super.approve(spender, amount);
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public override {
        if (!isApprovable) revert NotApprovable();
        super.permit(owner, spender, value, deadline, v, r, s);
    }

    function setIsApprovable(bool _val) public {
        if (msg.sender != curve) revert NotRampBondingCurve();
        isApprovable = _val;
    }

    function setIsLiquidityMigrated(bool _val) public {
        if (msg.sender != curve) revert NotRampBondingCurve();
        isLiquidityMigrated = _val;
    }
}
