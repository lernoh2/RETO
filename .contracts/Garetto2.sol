// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";


contract Garetto2 is ERC777 {
    
    address public owner;
    address public redor1;
    address public redor2;
    uint256 public redAttempt = 100 ether;
    bool private redorsSet = false;

      event TransferSent(address from, address to, uint256 amount);

    constructor() ERC777("Garetto2", "G-ETTO2", new address[](0)) {
        _mint(msg.sender, 100000 * 10 ** 18, "", "");
        owner = msg.sender;
    }

      modifier onlyOwner() {
        require(msg.sender == owner, "You are not the owner.");
        _;
    }  


      function setRedors(address _redor1, address _redor2) external onlyOwner {
        require(!redorsSet, "Redistributors already set");
        require(_redor1 != address(0) && _redor2 != address(0), "Invalid addresses");
        redor1 = _redor1;
        redor2 = _redor2;
        redorsSet = true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
         address sender = _msgSender();

           if(sender != owner)  {
            //Block direct transfers to either redistributor
             require(to != redor1 && to != redor2, "Direct transfer to redistributors not allowed");
           }

            if (amount == 100 ether) {
            uint256 redor1Share = 50 ether;
            uint256 redor2Share = 30 ether;
            uint256 rest = 20 ether;

            _send(sender, redor1, redor1Share, "", "", true);
            emit TransferSent(sender, redor1, redor1Share);

            _send(sender, redor2, redor2Share, "", "", true);
            emit TransferSent(sender, redor2, redor2Share);

            _send(sender, to, rest, "", "", true);
            emit TransferSent(sender, to, rest);
        } else {
            _send(sender, to, amount, "", "", true);
            emit TransferSent(sender, to, amount);
        }

        return true;
    }
}