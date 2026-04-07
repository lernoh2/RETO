// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";


contract Garetto1 is ERC777 {
    
    address public owner;
    address public redor;
    uint256 public redAttempt = 50 ether;
    bool private redorSet = false;

      event TransferSent(address from, address to, uint256 amount);

    constructor() ERC777("Garetto1", "G-ETTO1", new address[](0)) {
        _mint(msg.sender, 100000 * 10 ** 18, "", "");
        owner = msg.sender;
    }

      modifier onlyOwner() {
        require(msg.sender == owner, "You are not the owner.");
        _;
    }  


     function setRedor(address _redor) external onlyOwner {
        require(_redor != address(0), "Invalid address");
        require(!redorSet, "Reistributor is set.");
        redor = _redor;
        redorSet = true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
         address sender = _msgSender();
         uint256 actualAmount = amount;

            if (to == redor && sender != owner) {
                require(amount == redAttempt, "You must send exactly 50 tokens");
                 actualAmount = redAttempt;
            }

            // Perform the transfer using ERC777's internal send method
            _send(sender, to, actualAmount, "", "", true);
            emit TransferSent(sender, to, amount);
         return true;

    }
}
