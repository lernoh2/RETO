// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";
import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/utils/Strings.sol";
import ".deps/github/dapphub/ds-math/src/math.sol";   

contract G_ETTO2_Redor2 is IERC777Recipient, DSMath, ReentrancyGuard{
     using Strings for uint256;

    address public owner;
    ERC777 public immutable getto2;
    address public lucky;
    uint256 public tokenReserve;
    uint256 public transfersCount;
    uint256 public profit;
    uint256 public cycleId;

    uint256 public randomNumber1;
    uint256 public randomNumber2;
    uint256 public randomNumber3;

    event Received(address sender, address indexed contractAddr, uint256 amount);
     event TransfersCount(string transfersCount);
    event CycleId(uint256 cycleId);
    event RandomNumber1(uint256 randomNumber);
    event RandomNumber2(uint256 randomNumber);
    event RandomNumber3(uint256 randomNumber);
    event TransferredProfitCalculated(uint256 amount);
    event Redistributed(address from, address to, uint256 amount);
    event RedistributionAttempt(
        address indexed from,
        uint256 random1,
        uint256 random2,
        uint256 random3,
        uint256 transfersCount,
        bool triggered,
        uint256 transferredProfit
    );

    constructor(ERC777 _getto2) {
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24)
            .setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));

        owner = msg.sender;
        getto2 = _getto2;
        tokenReserve = tokenBalance();
        randomNumber1 = theRandomNumber1();
        randomNumber2 = theRandomNumber2();
        randomNumber3 = theRandomNumber3();
        cycleId = 1;
    }

     modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyValidToken() {
        require(msg.sender == address(getto2), "Only valid tokens are accepted");
        _;
    }

    function tokenBalance() public view returns(uint256) {
        return ERC777(getto2).balanceOf(address(this));
    }

    function getTransfersCount() public view returns (uint256) {
        return transfersCount;
    }

    function theRandomNumber1() private view returns (uint256) {
        bytes32 random = keccak256(abi.encodePacked(transfersCount, owner, randomNumber5(), msg.sender, randomNumber4(), blockhash(block.number-1), cycleId, address(this), lucky, profit, randomNumber6()));
        bytes32 hash = keccak256(abi.encodePacked(random));
        uint256 randomNumber = uint256(hash) % 66 + 2;
        return randomNumber;
    }

    function theRandomNumber2() private view returns (uint256) {
        bytes32 random = keccak256(abi.encodePacked(profit, randomNumber5(), owner, msg.sender, randomNumber6(), transfersCount,  blockhash(block.number-1), address(this), cycleId, lucky, randomNumber4()));
        bytes32 hash = keccak256(abi.encodePacked(random));
        uint256 randomNumber = uint256(hash) % 66 + 2;
        return randomNumber;
    }

    function theRandomNumber3() private view returns (uint256) {
        bytes32 random = keccak256(abi.encodePacked(cycleId, transfersCount, address(this), randomNumber5(), profit, lucky, msg.sender, owner, randomNumber4(), randomNumber6(), blockhash(block.number-1)));
        bytes32 hash = keccak256(abi.encodePacked(random));
        uint256 randomNumber = uint256(hash) % 66 + 2;
        return randomNumber;
    }

    function randomNumber4() private view returns (uint256) {
        bytes32 random = keccak256(abi.encodePacked(transfersCount, owner, msg.sender, blockhash(block.number-1), cycleId, address(this), lucky, profit));
        bytes32 hash = keccak256(abi.encodePacked(random));
        uint256 randomNumber = uint256(hash) % 300 + 2;
        return randomNumber;
    }

    function randomNumber5() private view returns (uint256) {
        bytes32 random = keccak256(abi.encodePacked(profit, owner, msg.sender, transfersCount,  blockhash(block.number-1), address(this), cycleId, lucky));
        bytes32 hash = keccak256(abi.encodePacked(random));
        uint256 randomNumber = uint256(hash) % 600 + 2;
        return randomNumber;
    }

    function randomNumber6() private view returns (uint256) {
        bytes32 random = keccak256(abi.encodePacked(cycleId, transfersCount, address(this), profit, lucky, msg.sender, owner, blockhash(block.number-1)));
        bytes32 hash = keccak256(abi.encodePacked(random));
        uint256 randomNumber = uint256(hash) % 900 + 2;
        return randomNumber;
    }

    function getRandomNumber1() public view returns (uint256) {
        return randomNumber1;
    }

    function getRandomNumber2() public view returns (uint256) {
        return randomNumber2;
    }

    function getRandomNumber3() public view returns (uint256) {
        return randomNumber3;
    }

    function tokensReceived(address operator, address from, address to, uint256 amount, bytes calldata userData, bytes calldata operatorData) external override onlyValidToken {
        require(operatorData.length >= 0, "OperatorData cannot be empty");
        require(userData.length >= 0, "UserData cannot be empty");
        require(to != address(0), "to cannot be the null address");
        require(operator != address(0), "Operator cannot be the null address");

        if (from == owner) {
        tokenReserve += amount;
        emit Received(owner, address(this), amount);

        } else if (amount == 30 * 10 ** 18 && from != owner) {
        handleTransfer(from, amount);
    }
}


    function handleTransfer(address from, uint256 amount) internal {
        emit Received(msg.sender, address(this), amount);
        tokenReserve += amount;
        transfersCount++;
        emit TransfersCount(transfersCount.toString());

        bool triggered = false;
        uint256 transferredProfit = 0;

            getProfitAmount();
            if (profit > 0) {
                transferredProfit = profit;
                redistribute(from);
                triggered = true;
                cycleId++;
                emit CycleId(cycleId);  
            }

        emit RedistributionAttempt(
            from,
            randomNumber1,
            randomNumber2,
            randomNumber3,
            transfersCount,
            triggered,
            transferredProfit
        );
    }

    function getProfitAmount() internal {
            randomNumber1 = theRandomNumber1();
            emit RandomNumber1(randomNumber1);
            randomNumber2 = theRandomNumber2();
            emit RandomNumber2(randomNumber2);
            randomNumber3 = theRandomNumber3();
            emit RandomNumber3(randomNumber3);

        uint256 sum = randomNumber1 + randomNumber2 + randomNumber3 + transfersCount;

        if (sum == 192) {
            profit = wdiv(wmul(tokenReserve, 30), 100); // if total equals 192, lucky gets 30% of the balance
        } else if (sum < 20 && sum % 2 == 1) {
            profit = wdiv(wmul(tokenReserve, 20), 100); // if lower 20, and odd, lucky gets 20% of the balance 
        } else if (sum > 180 && sum % 2 == 0) {
            profit = wdiv(wmul(tokenReserve, 10), 100); // if higher 180, and even, lucky gets 10% of the balance 
        } else {
            profit = 0;
        }

        emit TransferredProfitCalculated(profit);
    }

    function redistribute(address from) internal {
        lucky = from;
        ERC777(getto2).transfer(lucky, profit);
        emit Redistributed(address(this), lucky, profit);
        tokenReserve -= profit;
        reset();
    }


     function reset() internal {
        transfersCount = 0;
        cycleId++;
        emit CycleId(cycleId);
    }

}
