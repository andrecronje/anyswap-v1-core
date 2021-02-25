// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.1;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != 0x0 && codehash != accountHash);
    }
}

library SafeERC20 {
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint value) internal {
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }
    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

contract AnyswapV1Vault {
    using SafeERC20 for IERC20;

    address private _oldMPC;
    address private _newMPC;
    uint256 private _newMPCEffectiveTime;


    event LogChangeMPC(address indexed oldMPC, address indexed newMPC, uint indexed effectiveTime, uint chainID);
    event LogAnySwapOut(bytes32 indexed txhash, address indexed token, address indexed to, uint amount, uint chainID);
    event LogAnySwapIn(address indexed token, address indexed from, address indexed to, uint amount, uint chainID);
    event LogAnyCallQueue(address indexed callContract, uint value, bytes data, uint chainID);
    event LogAnyCallExecute(address indexed callContract, uint value, bytes data, bool success, uint chainID);

    modifier onlyMPC() {
        require(msg.sender == mpc(), "AnyswapV1Safe: FORBIDDEN");
        _;
    }

    function mpc() public view returns (address) {
        if (block.timestamp >= _newMPCEffectiveTime) {
            return _newMPC;
        }
        return _oldMPC;
    }

    function chainID() public view returns (uint id) {
        assembly {id := chainid()}
    }


    function changeMPC(address newMPC) public onlyMPC returns (bool) {
        require(newMPC != address(0), "AnyswapV1Safe: address(0x0)");
        _oldMPC = mpc();
        _newMPC = newMPC;
        _newMPCEffectiveTime = block.timestamp + 2*24*3600;
        emit LogChangeMPC(_oldMPC, _newMPC, _newMPCEffectiveTime, chainID());
        return true;
    }

    // Transfer tokens to the contract to be held on this side on the bridge
    function anySwapIn(address[] calldata tokens, address[] calldata to, uint[] calldata amounts, uint[] calldata chainIDs) public {
        for (uint i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);
            emit LogAnySwapIn(tokens[i], msg.sender, to[i], amounts[i], chainIDs[i]);
        }
    }

    // Transfer tokens out of the contract with redemption on other side
    function anySwapOut(bytes32[] calldata txs, address[] calldata tokens, address[] calldata to, uint256[] calldata amounts) public onlyMPC {
        for (uint i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransfer(to[i], amounts[i]);
            emit LogAnySwapOut(txs[i], tokens[i], to[i], amounts[i], chainID());
        }
    }

    // Call contract for arbitrary execution
    function anyCall(uint[] calldata values, address[] calldata contracts, bytes[] calldata data) external onlyMPC {
        bool success;
        for (uint i = 0; i < contracts.length; i++) {
            if (data[i].length > 0) (success,) = contracts[i].call{value:values[i]}(data[i]);
            emit LogAnyCallExecute(contracts[i], values[i], data[i], success, chainID());
        }
    }

    // Queue cross-chain contract event
    function anyQueue(uint[] calldata values, address[] calldata contracts, bytes[] calldata data, uint[] calldata chainIDs) external {
        for (uint i = 0; i < contracts.length; i++) {
            emit LogAnyCallQueue(contracts[i], values[i], data[i], chainIDs[i]);
        }
    }

    constructor(address _mpc) {
        _newMPC = _mpc;
        _newMPCEffectiveTime = block.timestamp;
    }
}
