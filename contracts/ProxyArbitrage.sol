pragma solidity 0.5.12;

// import "./IUniswapV2Router02.sol";
import "./BPool.sol";
import "./SafeMath.sol";

// Have to approve balancer Pools addresses for all token pairs involved
// Ensure that the ProxyArbitrage has wETH to execute the transaction
contract ProxyArbitrage {
    address internal constant UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant WETH_ADDRESS = 0xa0f764E120459bca39dB7E57a0cE975a489aB4fa;
    uint internal constant MAX_SLIPPAGE_PERCENTAGE = 200; // 2%

    event BalancerArbitrageEvent(
        address tokenIn,
        address tokenOut,
        uint256 tokenAmountIn,
        uint tokenAmountOut,
        uint spotPrice,
        uint256 maxPrice,
        uint256 minAmountOut
    );

    constructor() public {
        // uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
        // Pool wETH/YFI : 0x1a690056370c63AF824050d2290D3160096661eE
        // Pool YFI / MYX: 0x32741a08c02cb0f72f7e3bd4bba4aeca455b34bc
        // Amount : 50000000000000000000 wETH
    }

    /**
     * description: Main function to trigger arbitrage in many Uniswap/Balancer pools.
     *              This function requires ProxyArbitrage to hold wETH tokens
     */
    function arbitrage(address balancerPool1, address balancerPool2, uint256 wethAmount) public {
        uint tokenAmountOut = swapBalancerPool(balancerPool1, wethAmount);
        swapBalancerPool(balancerPool2, tokenAmountOut);
    }


    /**
     * description: Internal function that trigger trades in Balancer Pools
     * param address balancerPoolAddress: Balancer's pool address
     * param uint256 tokenAmountIn: Amount of token to trade in
     */
    function swapBalancerPool(address balancerPoolAddress, uint256 tokenAmountIn) internal returns (uint) {
        BPool pool = BPool(balancerPoolAddress);

        // Retrieve the ERC20 token addresses for the `balancerPoolAddress`
        address[] memory tokens = pool.getCurrentTokens();

        // Find the current price for the pair
        uint spotPrice = pool.getSpotPrice(tokens[0], tokens[1]);

        // Approve the pool from the ERC20 pairs for the ProxyArbitrage smart contract
        approveContract(tokens[0], balancerPoolAddress, tokenAmountIn);
        approveContract(tokens[1], balancerPoolAddress, tokenAmountIn);

        // Calculate MaxPrice and MinAmountOut based on `MAX_SLIPPAGE_PERCENTAGE`
        uint256 maxPrice = SafeMath.add(spotPrice, calculatePercentage(spotPrice, MAX_SLIPPAGE_PERCENTAGE));
        uint256 minAmountOut = SafeMath.mul(SafeMath.div(tokenAmountIn, maxPrice), 1 ether);

        // Execute the exchange
        (uint tokenAmountOut,) = pool.swapExactAmountIn(tokens[0], tokenAmountIn, tokens[1], minAmountOut, maxPrice);
        emit BalancerArbitrageEvent(tokens[0], tokens[1], tokenAmountIn, tokenAmountOut, spotPrice, maxPrice, minAmountOut);
    }

    /**
     * description: Calculate percentage
     * param uint amount: Amount
     * param uint percentage: percentage
     * return uint256: Amount * percentage/100
     */
    function calculatePercentage(uint amount, uint percentage) pure internal returns (uint256)  {
        return SafeMath.div(SafeMath.mul(amount, percentage), 10000);
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


    /**
     * description: function to transfer wETH to the ProxyArbitrage contract
     * param uint256 wethAmount: Amount in Wei of WETH to transfer to the ProxyArbitrage contract
     */
    // function transferWETHToProxy(uint256 wethAmount) internal {
    //     IERC20 token = IERC20(WETH_ADDRESS);
    //     token.transfer(address(this), wethAmount);
    // }
}
