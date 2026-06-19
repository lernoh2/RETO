// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";

contract Garetto_Airdrop is IERC777Recipient, ReentrancyGuard {

    address public owner;
    ERC777 public immutable token;
     uint256 public constant AIRDROP_AMOUNT = 50000 ether;

    mapping(address => bool) public claimed;
     // ===== RESERVES =====
    uint256 public reserve;
 

    // ===== EVENTS =====
    event Claimed(address indexed user, uint256 amount);
    event Deposited(uint256 amount);
   
   

    constructor(ERC777 _token) {
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24)
            .setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));

        owner = msg.sender;
        token = _token;
    
    }

    modifier onlyValidToken() {
        require(msg.sender == address(token), "Invalid token");
        _;
    }

    // ===== ENTRY =====
    function tokensReceived(
        address,
        address from,
        address,
        uint256 amount,
        bytes calldata,
        bytes calldata
    ) external override onlyValidToken {

        require(from != address(0), "Invalid sender");
        emit Deposited(amount);
}

  
function claim() external nonReentrant {
    address to = msg.sender;

    require(to.code.length == 0, "contracts not allowed");
    require(!claimed[to], "Already claimed");
    require(token.balanceOf(address(this)) >= AIRDROP_AMOUNT, "insufficient");

    claimed[to] = true;

    token.send(to, AIRDROP_AMOUNT, "");

    emit Claimed(to, AIRDROP_AMOUNT);
}

    function contractBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

}
