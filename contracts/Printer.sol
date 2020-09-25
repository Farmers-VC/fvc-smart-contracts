pragma solidity 0.5.12;

import "./balancer/BPool.sol";
import "./uniswap/IUniswapV2Pair.sol";
import "./uniswap/IUniswapV2Router02.sol";
import "./libraries/SafeMath.sol";


contract Printer {
    address payable private _owner;
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    IERC20 wethToken = IERC20(WETH_ADDRESS);
    enum PoolType { BALANCER, UNISWAP, SUSHISWAP }
    bool public _active;

    constructor() public {
        _owner = msg.sender;
        _active = true;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "caller is not the owner");
        _;
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

    function arbitrage(
        address[] calldata path,
        PoolType[] calldata poolType,
        uint256[] calldata minAmountOuts,
        uint256 ethAmountIn,
        uint256 estimateGasCost,
        uint256 maxBlockNumber
        ) external onlyOwner {
        require(_active, 'Contract is inactive');
        require(block.number < maxBlockNumber, 'Tx > maxBlockNumber');

        uint256 startEthAmount = wethToken.balanceOf(address(this));
        uint256 currentAmount = ethAmountIn;
        address currentAddress = WETH_ADDRESS;

        for(uint i; i < path.length; i++){
            if (poolType[i] == PoolType.UNISWAP) {
                (currentAmount, currentAddress) = swapUniswapPool(path[i], currentAmount, minAmountOuts[i], currentAddress, UNISWAP_ROUTER);
            } else if (poolType[i] == PoolType.BALANCER) {
                (currentAmount, currentAddress) = swapBalancerPool(path[i], currentAmount, minAmountOuts[i], currentAddress);
            } else if (poolType[i] == PoolType.SUSHISWAP) {
                (currentAmount, currentAddress) = swapUniswapPool(path[i], currentAmount, minAmountOuts[i], currentAddress, SUSHISWAP_ROUTER);
            }
        }

        require(currentAddress == WETH_ADDRESS, 'Last token not WETH');
        require(wethToken.balanceOf(address(this)) >= (startEthAmount + estimateGasCost), 'Tx loses WETH');
    }

    function swapBalancerPool(address balancerPoolAddress, uint256 tokenAmountIn, uint256 minAmountOut, address tokenInAddress) internal returns (uint256 tokenOutAmount, address tokenOutAddress) {
        address[] memory tokens = BPool(balancerPoolAddress).getCurrentTokens();
        tokenOutAddress = getTokenOutAddress(tokenInAddress, tokens[0], tokens[1]);

        approveContract(tokens[0], balancerPoolAddress, tokenAmountIn);
        approveContract(tokens[1], balancerPoolAddress, tokenAmountIn);

        (tokenOutAmount,) = BPool(balancerPoolAddress).swapExactAmountIn(
            tokenInAddress,
            tokenAmountIn,
            tokenOutAddress,
            minAmountOut,
            SafeMath.mul(BPool(balancerPoolAddress).getSpotPrice(tokens[0], tokens[1]), 2));
    }

    function swapUniswapPool(address pairAddress, uint256 tokenAmountIn, uint256 minAmountOut, address tokenInAddress, address routerAddress) internal returns (uint256 tokenOutAmount, address tokenOutAddress)  {
        tokenOutAddress = getTokenOutAddress(
            tokenInAddress,
            IUniswapV2Pair(pairAddress).token0(),
            IUniswapV2Pair(pairAddress).token1());

        approveContract(tokenInAddress, routerAddress, tokenAmountIn);
        approveContract(tokenOutAddress, routerAddress, tokenAmountIn);

        address[] memory orderedAddresses = new address[](2);
        orderedAddresses[0] = tokenInAddress;
        orderedAddresses[1] = tokenOutAddress;

        IUniswapV2Router02(routerAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmountIn,
            minAmountOut,
            orderedAddresses,
            address(this),
            block.timestamp + 30
        );
        tokenOutAmount = IERC20(tokenOutAddress).balanceOf(address(this));
    }

    function getTokenOutAddress(address tokenInAddress, address token0, address token1) internal pure returns (address tokenOutAddress) {
        if (token0 == tokenInAddress) {
            tokenOutAddress = token1;
        } else {
            tokenOutAddress = token0;
        }
    }

    function approveContract(address tokenAddress, address spender, uint amount) internal {
        if (IERC20(tokenAddress).allowance(address(this), spender) < amount) {
            IERC20(tokenAddress).approve(spender, 999999 ether);
        }
    }
}
