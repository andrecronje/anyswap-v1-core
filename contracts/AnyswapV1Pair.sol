// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.6.12;

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

interface IAnyswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function migrator() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
    function setMigrator(address) external;
}

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)

library SafeMathAnyswap {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
}

contract AnyswapV2ERC20 {
    using SafeMathAnyswap for uint;

    string public constant name = 'SushiSwap LP Token';
    string public constant symbol = 'SLP';
    uint8 public constant decimals = 18;
    uint  public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    constructor() public {
        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    function _mint(address to, uint value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint value) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (allowance[from][msg.sender] != uint(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'AnyswapV2: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'AnyswapV2: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }
}

// a library for performing various math operations

library Math {
    function min(uint x, uint y) internal pure returns (uint z) {
        z = x < y ? x : y;
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

// a library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format))

// range: [0, 2**112 - 1]
// resolution: 1 / 2**112

library UQ112x112 {
    uint224 constant Q112 = 2**112;

    // encode a uint112 as a UQ112x112
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112; // never overflows
    }

    // divide a UQ112x112 by a uint112, returning a UQ112x112
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}

interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

contract AnyswapV1Pair is AnyswapV2ERC20 {
    using SafeERC20 for IERC20;
    using SafeMathAnyswap for uint;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public immutable token0;
    address public immutable token1;
    address public immutable token;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint private unlocked = 1;

    address private _oldMPC;
    address private _newMPC;
    uint256 private _newMPCEffectiveTime;
    modifier lock() {
        require(unlocked == 1, 'AnyswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }


    modifier onlyMPC() {
        require(msg.sender == mpc(), "AnyswapV2: FORBIDDEN");
        _;
    }
    function mpc() public view returns (address) {
        if (block.timestamp >= _newMPCEffectiveTime) {
            return _newMPC;
        }
        return _oldMPC;
    }

    function changeMPCOwner(address newMPC) public onlyMPC returns (bool) {
        require(newMPC != address(0), "AnyswapV2: address(0x0)");
        _oldMPC = mpc();
        _newMPC = newMPC;
        _newMPCEffectiveTime = block.timestamp + 2*24*3600;
        emit LogChangeDCRMOwner(_oldMPC, _newMPC, _newMPCEffectiveTime);
        return true;
    }

    function getAmountOut(address tokenIn, uint amountIn) external view returns (uint amountOut) {
         (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
         if (tokenIn == token0) {
             return _getAmountOut(amountIn, _reserve0, _reserve1);
         } else {
             return _getAmountOut(amountIn, _reserve1, _reserve0);
         }
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function _getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function getAmountIn(address tokenOut, uint amountOut) external view returns (uint amountIn) {
         (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
         if (tokenOut == token0) {
             return _getAmountIn(amountOut, _reserve1, _reserve0);
         } else {
             return _getAmountIn(amountOut, _reserve0, _reserve1);
         }
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function _getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event AnySwap(
        address indexed sender,
        uint amountIn,
        uint amountOut,
        address indexed to,
        address indexed callContract,
        uint value,
        bytes data
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    event LogChangeDCRMOwner(address indexed oldOwner, address indexed newOwner, uint indexed effectiveTime);
    event LogSwapin(bytes32 indexed txhash, address indexed account, uint amount);
    event LogSwapout(address indexed account, address indexed bindaddr, uint amount);

    constructor(address _token0, address _token1, address _token, address _mpc) public {
        require(_token == _token0 || _token == _token1);

        _newMPC = _mpc;
        _newMPCEffectiveTime = block.timestamp;

        token0 = _token0;
        token1 = _token1;
        token = _token;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'AnyswapV2: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address from, address to, uint amount0, uint amount1) external lock returns (uint liquidity) {
        require(msg.sender == mpc(), 'AnyswapV2: FORBIDDEN');
        address _token = token;
        uint _amount = _token == token0 ? amount0 : amount1;
        IERC20(_token).safeTransferFrom(from, address(this), _amount);

        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint balance0 = amount0.add(_reserve0);
        uint balance1 = amount1.add(_reserve1);

        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'AnyswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1);
        emit Mint(to, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address from, address to, uint liquidity) external lock returns (uint amount0, uint amount1) {
        require(msg.sender == mpc(), 'AnyswapV2: FORBIDDEN');
        (uint256 _reserve0, uint256 _reserve1,) = getReserves(); // gas savings

        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(_reserve0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(_reserve1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'AnyswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(from, liquidity);
        address _token = token;
        uint _amount = _token == token0 ? amount0 : amount1;
        IERC20(_token).safeTransfer(to, _amount);

        _reserve0 = _reserve0.sub(amount0);
        _reserve1 = _reserve1.sub(amount1);

        _update(_reserve0, _reserve1);
        emit Burn(from, amount0, amount1, to);
    }


    // used for any user to swap in `token` for `amountIn` and specify `amountOut`
    function swap(uint amountIn, uint amountOut, address to, uint value, address callContract, bytes memory data) external lock {
        require(amountOut > 0, 'AnyswapV2: INSUFFICIENT_OUTPUT_AMOUNT');

        address _token = token;
        address _token0 = token0;
        IERC20(_token).safeTransferFrom(msg.sender, address(this), amountIn);

        (uint _amount0In, uint _amount1In) = _token == _token0 ? (amountIn, uint(0)) : (uint(0), amountIn);
        (uint _amount0Out, uint _amount1Out) = _token == _token0 ? (uint(0), amountOut) : (amountOut, uint(0));

        {
        (uint _reserve0, uint _reserve1,) = getReserves(); // gas savings
        require(_amount0Out < _reserve0 && _amount1Out < _reserve1, 'AnyswapV2: INSUFFICIENT_LIQUIDITY');
        }

        {
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'AnyswapV2: INVALID_TO');
        }

        _swap(_amount0In, _amount1In, _amount0Out, _amount1Out);
        emit AnySwap(msg.sender, amountIn, amountOut, to, callContract, value, data);
    }

    // used by MPC bridge for an output tx given an input txs
    function anySwap(uint amountIn, uint amountOut, address to, uint value, address callContract, bytes memory data) external lock {
        require(msg.sender == mpc(), 'AnyswapV2: FORBIDDEN');
        require(amountOut > 0, 'AnyswapV2: INSUFFICIENT_OUTPUT_AMOUNT');

        address _token = token;
        address _token0 = token0;

        if (data.length > 0) callContract.call{value:value}(data);

        (uint _amount0In, uint _amount1In) = _token == _token0 ? (amountIn, uint(0)) : (uint(0), amountIn);
        (uint _amount0Out, uint _amount1Out) = _token == _token0 ? (uint(0), amountOut) : (amountOut, uint(0));

        {
        (uint _reserve0, uint _reserve1,) = getReserves(); // gas savings
        require(_amount0Out < _reserve0 && _amount1Out < _reserve1, 'AnyswapV2: INSUFFICIENT_LIQUIDITY');
        }

        {
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'AnyswapV2: INVALID_TO');
        IERC20(_token).safeTransfer(to, amountOut); // optimistically transfer tokens
        }

        _swap(_amount0In, _amount1In, _amount0Out, _amount1Out);
        emit AnySwap(msg.sender, amountIn, amountOut, to, callContract, value, data);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function _swap(uint amount0In, uint amount1In, uint amount0Out, uint amount1Out) internal {
        (uint _reserve0, uint _reserve1,) = getReserves(); // gas savings

        uint _balance0;
        uint _balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
        _balance0 = _reserve0.sub(amount0Out).add(amount0In);
        _balance1 = _reserve1.sub(amount1Out).add(amount1In);
        }
        require(amount0In > 0 || amount1In > 0, 'AnyswapV2: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint _balance0Adjusted = _balance0.mul(1000).sub(amount0In.mul(3));
        uint _balance1Adjusted = _balance1.mul(1000).sub(amount1In.mul(3));
        require(_balance0Adjusted.mul(_balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'AnyswapV2: K');
        }

        _update(_balance0, _balance1);
    }

    // force balances to match reserves
    function sweep(address _token, address to, uint amount) external lock {
        require(msg.sender == mpc(), 'AnyswapV2: FORBIDDEN');
        require(_token != token, 'AnyswapV2: FORBIDDEN');
        IERC20(_token).safeTransfer(to, amount);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        require(msg.sender == mpc(), 'AnyswapV2: FORBIDDEN');
        address _token = token;
        (uint _reserve0, uint _reserve1,) = getReserves(); // gas savings
        uint _reserve = _token == token0 ? _reserve0 : _reserve1;
        IERC20(_token).safeTransfer(to, IERC20(_token).balanceOf(address(this))-_reserve);
    }

    // force reserves to match balances
    function sync(uint reserve) external lock {
        require(msg.sender == mpc(), 'AnyswapV2: FORBIDDEN');
        address _token = token;
        (uint _balance0, uint _balance1) = token == token0 ? (IERC20(_token).balanceOf(address(this)), reserve) : (reserve, IERC20(_token).balanceOf(address(this)));
        _update(_balance0, _balance1);
    }

    // force reserves to match balances
    function force(uint balance0, uint balance1) external lock {
        require(msg.sender == mpc(), 'AnyswapV2: FORBIDDEN');
        _update(balance0, balance1);
    }
}
