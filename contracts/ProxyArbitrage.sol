pragma solidity 0.5.12;

import "./balancer/BPool.sol";
import "./libraries/SafeMath.sol";
import './uniswap/UniswapV2Library.sol';
import "./uniswap/IUniswapV2Router02.sol";


// TEST DATA:
// balancerPool1 wETH/YFI : 0x1a690056370c63AF824050d2290D3160096661eE
// balancerPool2 YFI / MYX: 0x32741a08c02cb0f72f7e3bd4bba4aeca455b34bc
// uniswapPath = ["0x9657ff14c2D6d502113FDAD8166d1c14c085C2eC", "0xa0f764E120459bca39dB7E57a0cE975a489aB4fa"]  (MYX -> WETH)
// wethAmount : 50000000000000000000 wETH (50)   -  1000000000000000000 (1)

// ["0x1a690056370c63AF824050d2290D3160096661eE"],[0],"50000000000000000000","0"
// ["0xd47F4f7462E895298484AB83622C78647214C2ab"],[1],"50000000000000000000","0"
// ["0x1a690056370c63AF824050d2290D3160096661eE", "0x32741a08c02cb0f72f7e3bd4bba4aeca455b34bc", "0xd47F4f7462E895298484AB83622C78647214C2ab"],[0,"0",1],"50000000000000000000","0"


// Have to approve balancer Pools addresses for all token pairs involved
// Ensure that the ProxyArbitrage has wETH to execute the transaction
contract ProxyArbitrage {
    address payable private _owner;
    enum PoolType { BALANCER, UNISWAP }

    // Uniswap Factory and Router addresses should be the same on mainnet and testnets
    address internal constant UNISWAP_FACTORY_ADDRESS = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    
    // TODO!!! Change to real wETH ADDRESS for production
    address internal constant WETH_ADDRESS = 0xa0f764E120459bca39dB7E57a0cE975a489aB4fa;
    // uint internal constant MAX_SLIPPAGE_PERCENTAGE = 200; // 2%

    IUniswapV2Router02 internal uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
    

    constructor() public {
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }
  
    // Ability to withdraw eth
    function withdrawEth() public onlyOwner{
        address(_owner).transfer(address(this).balance);
    }
   
    // Ability to withdraw any token
    function withdrawToken(address tokenAddress) public onlyOwner{
        IERC20 token = IERC20(tokenAddress);
        token.transfer(address(_owner), token.balanceOf(address(this)));
    }

    /**
     * description: Main function to trigger arbitrage in many Uniswap/Balancer pools.
     *              This function requires ProxyArbitrage to hold wETH tokens
     */
    function arbitrage(address[] memory path, PoolType[] memory poolType, uint256 ethAmountIn, uint256 minAmountOut) public {
        require(path.length == poolType.length, 'Path and PoolType must be equal in length');
        require(minAmountOut > ethAmountIn, 'minAmountOut should be greater than amountIn.');
        
        uint256 tokenInAmount;
        uint256 tokenOutAmount;
        address tokenOutAddress;
        address tokenInAddress;
                
        for (uint8 i = 0; i < path.length; i++) { 
            if (i == 0) {
                // On first iteration, the token traded is always wETH
                tokenInAddress = WETH_ADDRESS;
                tokenInAmount = ethAmountIn;
            } else {
                tokenInAddress = tokenOutAddress;
                tokenInAmount = tokenOutAmount;
            }
            
            
            if (poolType[i] == PoolType.BALANCER) {
                (tokenOutAmount, tokenOutAddress) = swapBalancerPool(path[i], tokenInAmount, tokenInAddress);
            } else if (poolType[i] == PoolType.UNISWAP) {
                (tokenOutAmount, tokenOutAddress) = swapUniswapPool(path[i], tokenInAmount, tokenInAddress);
            } else{
                require(false, 'Invalid pooltype');   
            }
        }

        require(tokenOutAddress == WETH_ADDRESS, 'Final token needs to be WETH');
        require(tokenOutAmount >= minAmountOut, 'tokenOutAmount must be greater than minAmountOut');   
    }

    /**
     * description: Internal function that trigger trades in Balancer Pools
     * param address balancerPoolAddress: Balancer's pool address
     * param uint256 tokenAmountIn: Amount of token to trade in
     */
    function swapBalancerPool(address balancerPoolAddress, uint256 tokenAmountIn, address tokenInAddress) internal returns (uint256 tokenOutAmount, address tokenOutAddress) {
        BPool pool = BPool(balancerPoolAddress);

        // Retrieve the ERC20 token addresses for the `balancerPoolAddress`
        address[] memory tokens = pool.getCurrentTokens();

        tokenOutAddress = getTokenOut(tokenInAddress, tokens[0], tokens[1]);

        // Find the current price for the pair
        uint256 spotPrice = pool.getSpotPrice(tokens[0], tokens[1]);

        // Approve the pool from the ERC20 pairs for the ProxyArbitrage smart contract
        approveContract(tokens[0], balancerPoolAddress, tokenAmountIn);
        approveContract(tokens[1], balancerPoolAddress, tokenAmountIn);

        // Calculate MaxPrice and MinAmountOut based on `MAX_SLIPPAGE_PERCENTAGE`
        uint256 maxPrice = SafeMath.mul(spotPrice, 2); //SafeMath.add(spotPrice, calculatePercentage(spotPrice, MAX_SLIPPAGE_PERCENTAGE));
        uint256 minAmountOut = 0;

        // Execute the exchange
        (tokenOutAmount,) = pool.swapExactAmountIn(tokenInAddress, tokenAmountIn, tokenOutAddress, minAmountOut, maxPrice);
    }


    function swapUniswapPool(address pairAddress, uint256 tokenAmountIn, address tokenInAddress) internal returns (uint256 tokenOutAmount, address tokenOutAddress)  {
        IUniswapV2Pair pairContract = IUniswapV2Pair(pairAddress);
        address token0 = pairContract.token0();
        address token1 = pairContract.token1();
        
        tokenOutAddress = getTokenOut(tokenInAddress, token0, token1);

        // Approve the pool from the ERC20 pairs for this smart contract
        approveContract(tokenInAddress, UNISWAP_ROUTER_ADDRESS, tokenAmountIn);
        approveContract(tokenOutAddress, UNISWAP_ROUTER_ADDRESS, tokenAmountIn);

        address[] memory orderedAddresses = new address[](2);
        orderedAddresses[0] = tokenInAddress;
        orderedAddresses[1] = tokenOutAddress;
        
        uint256 deadline = block.timestamp + 30; // 2 block deadline
        uint256 minAmountOut = 0; //calcUniswapMinAmountOut(pairContract, tokenAmountIn, tokenInAddress),
        tokenOutAmount = uniswapRouter.swapExactTokensForTokens(
            tokenAmountIn,
            minAmountOut,
            orderedAddresses,
            address(this),
            deadline
        )[0];
    }

    function getTokenOut(address tokenInAddress, address token0, address token1) internal pure returns (address tokenOutAddress) {
        if (token0 == tokenInAddress) {
            tokenOutAddress = token1;
        } else {
            tokenOutAddress = token0;
        }     
    }

     /**
     * description: Approve the pool to move ERC20 tokens on behalf of the ProxyArbitrage contract
     * param address tokenAddress: ERC20 token address
     * param uint256 pool: Balancer or Uniswap pool
     * param uint amount: amount to transfer (ensure that the alloance is at least >= amount)
     */
    function approveContract(address tokenAddress, address poolAddress, uint amount) internal {
        IERC20 token = IERC20(tokenAddress);

        if (token.allowance(address(this), poolAddress) < amount) {
            token.approve(poolAddress, 99999999999 ether);
        }
    }   

    // function calcUniswapMinAmountOut(IUniswapV2Pair pairContract, uint256 amountIn, address tokenIn) internal view returns (uint256 minAmountOut) {
    //     uint112 reserve0;
    //     uint112 reserve1;
    //     uint32 blockTimestampLast;
    //     (reserve0, reserve1, blockTimestampLast) = pairContract.getReserves();

    //     if (pairContract.token0() == tokenIn) {
    //         minAmountOut = uniswapQuote(amountIn, reserve0, reserve1);
    //     } else {
    //         minAmountOut = uniswapQuote(amountIn, reserve1, reserve0);
    //     }
    // }

    // function uniswapQuote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
    //     require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
    //     require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
    //     amountB = SafeMath.div(SafeMath.mul(amountA, reserveB), reserveA);
    // }
    
    // /**
    //  * description: Calculate percentage
    //  * param uint amount: Amount
    //  * param uint percentage: percentage
    //  * return uint256: Amount * percentage/100
    //  */
    // function calculatePercentage(uint amount, uint percentage) pure internal returns (uint256)  {
    //     return SafeMath.div(SafeMath.mul(amount, percentage), 10000);
    // }

}

