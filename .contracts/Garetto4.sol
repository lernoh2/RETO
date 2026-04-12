// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";

contract GarettoTokenVersion9 is ERC777 {

    address public owner;
    address public redistributor;

    // ===== Fee config =====
    uint256 public constant FEE_BPS = 50; // 0.5%
    uint256 public constant BPS_DENOM = 10000;

    // ===== Minimum transfer =====
    uint256 public minTransferAmount = 0.001 ether;

    // ===== Fee exemptions =====
    mapping(address => bool) public isFeeExempt;

    // ===== Internal guards =====
    bool private _isInternalTransfer;
    bool public redistributorSet = false;

    // ===== Events =====
    event FeeTaken(address indexed from, uint256 fee);
    event MinTransferUpdated(uint256 newMin);
    event RedistributorSet(address indexed redistributor);
    

     constructor() ERC777("Garetto_V9", "G-ETTO_V9", new address[](0)) {
        _mint(msg.sender, 10000000 * 10 ** 18, "", "");
        owner = msg.sender;
        isFeeExempt[msg.sender] = true;
    }
        
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ===== Admin =====

    function setRedistributor(address _redistributor) external onlyOwner {
        require(!redistributorSet, "Redistributor already set");
        require(_redistributor != address(0), "Invalid address");

        redistributor = _redistributor;
        redistributorSet = true;

        emit RedistributorSet(_redistributor);
    }

    function setFeeExempt(address account, bool exempt) external onlyOwner {
        isFeeExempt[account] = exempt;
    }

    function setMinTransferAmount(uint256 newMin) external onlyOwner {
        require(newMin > 0, "Min must be > 0");
        minTransferAmount = newMin;
        emit MinTransferUpdated(newMin);
    }

    // ===== Core Logic =====

function transfer(address to, uint256 amount) public override returns (bool) {

    address from = _msgSender();

    // Block direct transfers to redistributor
    if (to == redistributor) {
        revert("Direct transfers to redistributor not allowed");
    }

    // Min transfer (except owner)
    if (from != owner) {
        require(amount >= minTransferAmount, "Below minimum transfer amount");
    }

    // Apply fee
    if (!isFeeExempt[from] && redistributor != address(0)) {

        uint256 fee = (amount * FEE_BPS) / BPS_DENOM;
        uint256 remaining = amount - fee;

        // Send fee (NO HOOKS)
        _send(from, redistributor, fee, "", "", false);
        emit FeeTaken(from, fee);

        // Send remaining
        _send(from, to, remaining, "", "", false);

    } else {
        _send(from, to, amount, "", "", false);
    }

    return true;
}
}