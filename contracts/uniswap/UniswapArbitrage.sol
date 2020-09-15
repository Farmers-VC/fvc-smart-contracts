pragma solidity =0.6.6;

import "./libraries/SafeMath.sol";
import './libraries/UniswapV2Library.sol';

import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IERC20.sol";

contract UniswapArbitrage {
    address internal constant UNISWAP_FACTORY_ADDRESS = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IUniswapV2Router02 internal uniswapRouter;
    
    constructor() public {
        uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
    }
    
    function trade(uint256 wethAmount, address[] memory path) public {
        // path[0] = address(0xa0f764E120459bca39dB7E57a0cE975a489aB4fa); //WETH
        // path[1] = address(0x9657ff14c2D6d502113FDAD8166d1c14c085C2eC); //MYX
        
        // Get the Pair contract
        IUniswapV2Pair PairContract = getPairContract(path);
        
        // Approve the pool from the ERC20 pairs for this smart contract
        approveContract(path[0], wethAmount);
        approveContract(path[1], wethAmount);

        uint deadline = block.timestamp + 30; 
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            wethAmount, getMinAmountOut(PairContract, wethAmount, path[0]), path, address(this), deadline);
        
    }
    
    function getPairContract(address[] memory path) private pure returns (IUniswapV2Pair PairContract) {
        address pairAddress = UniswapV2Library.pairFor(UNISWAP_FACTORY_ADDRESS, path[0], path[1]);
        PairContract = IUniswapV2Pair(pairAddress);
    }
    
    function getMinAmountOut(IUniswapV2Pair PairContract, uint256 amount, address tokenIn) private view returns (uint256 minAmountOut) {
        uint112 reserve0; 
        uint112 reserve1; 
        uint32 blockTimestampLast; 
        (reserve0, reserve1, blockTimestampLast) = PairContract.getReserves();

        if(PairContract.token0() == tokenIn){
            minAmountOut = UniswapV2Library.quote(amount, reserve0, reserve1)
        }else{
            minAmountOut = UniswapV2Library.quote(amount, reserve1, reserve0)
        }        
    }
    

    function approveContract(address tokenAddress, uint256 amount) private {
        IERC20 token = IERC20(tokenAddress);
        if (token.allowance(address(this), UNISWAP_ROUTER_ADDRESS) < amount) {
            token.approve(UNISWAP_ROUTER_ADDRESS, 99999999999 ether);
        }
    }
}