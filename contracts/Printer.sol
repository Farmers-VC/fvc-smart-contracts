pragma solidity 0.5.12;

import "./BPool.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";
import "./SafeMath.sol";

contract PrinterV2 {
    using SafeMath for uint256;

    function arbitrage(
        address[7][3] calldata tokenPaths,
        uint256[3] calldata minAmountOuts,
        uint256 ethAmountIn,
        uint256 estimateGasCost,
        uint8[3] calldata poolType,
        uint64 maxBlockNumber
        ) external onlyExecutor {
        require(_active, 'Contract is inactive');
        require(block.number < maxBlockNumber, 'maxBlockNumber');
        IERC20 wethToken = IERC20(WETH_ADDRESS);
        uint256 startEthAmount = wethToken.balanceOf(address(this));
        uint256 currentAmount = ethAmountIn;
        for(uint i; i < tokenPaths.length; i++){
            if (poolType[i] == 1) {
                // Uniswap / SushiSwap type of swap
                currentAmount = swapUniswapPool(currentAmount, minAmountOuts[i], tokenPaths[i]);
            } else if (poolType[i] == 0) {
                // Balancer type of swap
                currentAmount = swapBalancerPool(currentAmount, minAmountOuts[i], tokenPaths[i][0], tokenPaths[i][1], tokenPaths[i][2]);
            }
        }
        require(wethToken.balanceOf(address(this)) >= startEthAmount.add(estimateGasCost), 'Tx loses WETH');
    }

    function unmask(address maskedAddress) internal pure returns (address unmaskedAddress) {
        unmaskedAddress = address(uint(maskedAddress) ^ uint(0x49a55f1e8EC5025deb60a38724004E21E8dC4eBe));
    }

    function swapBalancerPool(uint256 tokenAmountIn, uint256 minAmountOut, address poolAddress, address tokenInAddress, address tokenOutAddress)
    internal returns (uint256 tokenOutAmount)
    {
        approveContract(unmask(tokenInAddress), unmask(poolAddress), tokenAmountIn);
        (tokenOutAmount,) = BPool(unmask(poolAddress)).swapExactAmountIn(
            unmask(tokenInAddress),
            tokenAmountIn,
            unmask(tokenOutAddress),
            minAmountOut,
            999999999999000000000000000000);
    }

    function swapUniswapPool(uint256 tokenAmountIn, uint256 minAmountOut, address[7] memory tokenPaths)
    internal returns (uint256 tokenOutAmount)
    {
        // We store the number of tokens in `tokenPaths` in the last element of the array
        address[] memory orderedAddresses = new address[](uint(tokenPaths[tokenPaths.length - 1]));
        for (uint i; i < uint(tokenPaths[tokenPaths.length - 1]); i++) {
            orderedAddresses[i] = unmask(tokenPaths[i]);
        }
        // We store the Router address in the second to last element of the array in `tokenPaths`
        approveContract(orderedAddresses[0], tokenPaths[tokenPaths.length - 2], tokenAmountIn);
        IUniswapV2Router02(tokenPaths[tokenPaths.length - 2]).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmountIn,
            minAmountOut,
            orderedAddresses,
            address(this),
            2601891424
        );
        tokenOutAmount = IERC20(orderedAddresses[orderedAddresses.length - 1]).balanceOf(address(this));
    }

    function approveContract(address tokenAddress, address spender, uint amount) internal {
        if (IERC20(tokenAddress).allowance(address(this), spender) < amount) {
            IERC20(tokenAddress).approve(spender, 999999 ether);
        }
    }

    address payable private _owner;
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    mapping (address => bool) private executors;
    bool public _active;

    constructor() public {
        _owner = msg.sender;
        _active = true;
        executors[msg.sender] = true;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "caller is not the owner");
        _;
    }

    modifier onlyExecutor() {
        require(executors[msg.sender], "not executors");
        _;
    }

    function setExecutor(address executor, bool active) external onlyOwner {
        executors[executor] = active;
    }

    function withdrawEth() external onlyOwner {
        address(_owner).transfer(address(this).balance);
    }

    function withdrawToken(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).transfer(address(_owner), amount);
    }

    function toggleActive() external onlyOwner {
        _active = !_active;
    }

    function fake() external {
    }
}
