// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

contract OnlyOne is ERC20Permit {
    constructor() ERC20Permit("ONLYONE") ERC20("ONLY ONE", "ONE") {
        _mint(msg.sender, 100 * 10**18);
    }
}
