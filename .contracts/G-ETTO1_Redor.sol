// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "/.deps/github/OpenZeppelin/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "/.deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";
import "/.deps/github/OpenZeppelin/openzeppelin-contracts/contracts/utils/Strings.sol";
import "/.deps/github/dapphub/ds-math/src/math.sol";   

contract G_ETTO1_Redor1 is IERC777Recipient, DSMath, ReentrancyGuard {
    using Strings for uint256;

    address public owner;
    ERC777 public immutable getto1;
    address public lucky;
    uint256 public tokenReserve;
    uint256 private transfersCount;
    uint256 public profit;
    uint256 public cycleId;
    address private trustedSigner;
    uint256 public lastRandom;

    uint256 public randomNumber1;
    uint256 public randomNumber2;
    uint256 public randomNumber3;

    event RandomRequested(address indexed requester, uint256 requestId);
    event RandomReceived(uint256 random, address from);
    event RandomnessProvided(uint256 r1, uint256 r2, uint256 r3);
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

    constructor(ERC777 _getto1, address _trustedSigner) {
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24)
            .setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));
        owner = msg.sender;
        getto1 = _getto1;
        tokenReserve = tokenBalance();
        trustedSigner = _trustedSigner;
        cycleId = 1;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyValidToken() {
        require(msg.sender == address(getto1), "Only valid tokens are accepted");
        _;
    }

    function tokenBalance() public view returns (uint256) {
        return getto1.balanceOf(address(this));
    }

    function getTransfersCount() public view returns (uint256) {
        return transfersCount;
    }

    // Step 1: off-chain randomness trigger
    function requestRandom(uint256 requestId) external {
        emit RandomRequested(msg.sender, requestId);
    }

    // Step 2: off-chain randomness injection
    function provideRandomness(
        uint256 r1,
        uint256 r2,
        uint256 r3,
        bytes memory signature
    ) external {
        bytes32 message = prefixed(keccak256(abi.encodePacked(r1, r2, r3, address(this))));
        require(recoverSigner(message, signature) == trustedSigner, "Invalid signer");

        randomNumber1 = r1;
        randomNumber2 = r2;
        randomNumber3 = r3;

        emit RandomnessProvided(r1, r2, r3);
        emit RandomNumber1(r1);
        emit RandomNumber2(r2);
        emit RandomNumber3(r3);
    }

    function recoverSigner(bytes32 message, bytes memory sig) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(sig);

        return ecrecover(message, v, r, s);
    }

    function verify(uint256 random, bytes memory signature) public view returns (bool) {
        bytes32 message = prefixed(keccak256(abi.encodePacked(random)));
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        address signer = ecrecover(message, v, r, s);
        return signer == trustedSigner;
    }

    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function splitSignature(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid sig length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

      function tokensReceived(address operator, address from, address to, uint256 amount, bytes calldata userData, bytes calldata operatorData) external override onlyValidToken {
        require(operatorData.length >= 0, "OperatorData cannot be empty");
        require(userData.length >= 0, "UserData cannot be empty");
        require(to != address(0), "to cannot be the null address");
        require(operator != address(0), "Operator cannot be the null address");

        if (from == owner) {
        tokenReserve += amount;
        emit Received(owner, address(this), amount);

        } else if (amount == 50 * 10 ** 18 && from != owner) {
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
        uint256 sum = randomNumber1 + randomNumber2 + randomNumber3;

        if (sum == 88) {
            profit = wdiv(wmul(tokenReserve, 30), 100); // 30%
        } else if (sum < 20 && sum % 2 == 1) {
            profit = wdiv(wmul(tokenReserve, 20), 100); // 20%
        } else if (sum > 80 && sum % 2 == 0) {
            profit = wdiv(wmul(tokenReserve, 10), 100); // 10%
        } else {
            profit = 0;
        }

        emit TransferredProfitCalculated(profit);
    }

    function redistribute(address from) internal {
        lucky = from;
        getto1.transfer(lucky, profit);
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
