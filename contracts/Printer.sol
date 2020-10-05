pragma solidity 0.5.12;
pragma experimental ABIEncoderV2;

import "./BPool.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";
import "./SafeMath.sol";


contract PrinterV2 {
     function arbitrage(
        address[5][3] calldata tokenPaths,
        uint256[3] calldata minAmountOuts,
        uint256 ethAmountIn,
        uint256 estimateGasCost,
        uint8[3] calldata poolType,
        uint64 maxBlockNumber
        ) external onlyOwner {
        require(_active, 'Contract is inactive');
        require(block.number < maxBlockNumber, 'maxBlockNumber');

        uint256 startEthAmount = wethToken.balanceOf(address(this));
        uint256 currentAmount = ethAmountIn;
        for(uint i; i < tokenPaths.length; i++){
            if (poolType[i] == 1) {
                currentAmount = swapUniswapPool(currentAmount, minAmountOuts[i], tokenPaths[i], UNISWAP_ROUTER);
            } else if (poolType[i] == 0) {
                currentAmount = swapBalancerPool(currentAmount, minAmountOuts[i], tokenPaths[i][0], tokenPaths[i][1], tokenPaths[i][2]);
            } else if (poolType[i] == 2) {
                currentAmount = swapUniswapPool(currentAmount, minAmountOuts[i], tokenPaths[i], SUSHISWAP_ROUTER);
            }
        }

        require(wethToken.balanceOf(address(this)) >= SafeMath.add(startEthAmount, estimateGasCost), 'Tx loses WETH');
    }
    
    
    address payable private _owner;
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    IERC20 wethToken = IERC20(WETH_ADDRESS);
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
    

    function swapBalancerPool(uint256 tokenAmountIn, uint256 minAmountOut, address poolAddress, address tokenInAddress, address tokenOutAddress) 
    internal returns (uint256 tokenOutAmount) 
    {
        approveContract(tokenInAddress, poolAddress, tokenAmountIn);

        (tokenOutAmount,) = BPool(poolAddress).swapExactAmountIn(
            tokenInAddress,
            tokenAmountIn,
            tokenOutAddress,
            minAmountOut,
            999999999999000000000000000000);
    }

    function swapUniswapPool(uint256 tokenAmountIn, uint256 minAmountOut, address[5] memory tokenPaths, address routerAddress) 
    internal returns (uint256 tokenOutAmount)  
    {
        // We store the number of tokens in `tokenPaths` in the last element of the array
        address[] memory orderedAddresses = new address[](uint(tokenPaths[4]));
        for (uint i; i < uint(tokenPaths[4]); i++) {
            orderedAddresses[i] = tokenPaths[i];
        }

        approveContract(orderedAddresses[0], routerAddress, tokenAmountIn);
        
        IUniswapV2Router02(routerAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmountIn,
            minAmountOut,
            orderedAddresses,
            address(this),
            block.timestamp + 30
        );
        tokenOutAmount = IERC20(orderedAddresses[orderedAddresses.length - 1]).balanceOf(address(this));
    }


    function approveContract(address tokenAddress, address spender, uint amount) internal {
        if (IERC20(tokenAddress).allowance(address(this), spender) < amount) {
            IERC20(tokenAddress).approve(spender, 999999 ether);
        }
    }
}

