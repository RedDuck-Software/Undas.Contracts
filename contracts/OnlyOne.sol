// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

contract OnlyOne is ERC20Permit {
    constructor() ERC20Permit("Undas") ERC20("Undas", "Undas") {
        _mint(msg.sender, 100 * 10**18);
    }
}
