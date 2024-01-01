// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";

contract AttackerContract {
    address owner;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;

    constructor(address _selfiePool, address _dvtSnapshot, address _simpleGovernance) {
        owner = msg.sender;
        simpleGovernance = SimpleGovernance(_simpleGovernance);
        selfiePool = SelfiePool(_selfiePool);
        dvtSnapshot = DamnValuableTokenSnapshot(_dvtSnapshot);
    }
}

contract Selfie is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Attacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Simple Governance");

        selfiePool = new SelfiePool(address(dvtSnapshot), address(simpleGovernance));

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        //emit log_named_uint("snapshot selfiepool balance", dvtSnapshot.getBalanceAtLastSnapshot(address(selfiePool)));
        dvtSnapshot.snapshot();
        emit log_named_uint("snapshot selfiepool balance", dvtSnapshot.getBalanceAtLastSnapshot(address(selfiePool)));
        emit log_named_uint("snapshot this balance", dvtSnapshot.getBalanceAtLastSnapshot(address(this)));
        emit log_named_uint("snapshot attacker balance", dvtSnapshot.getBalanceAtLastSnapshot(address(attacker)));
        vm.startPrank(address(selfiePool));
        dvtSnapshot.transfer(attacker, 5e18);
        dvtSnapshot.snapshot();
        emit log_named_uint("snapshot attacker balance", dvtSnapshot.getBalanceAtLastSnapshot(address(attacker)));

        /**
         * EXPLOIT END
         *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}
