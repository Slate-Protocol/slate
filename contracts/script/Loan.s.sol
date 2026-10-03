// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StockLender} from "../src/examples/StockLender.sol";
import {IPoolManager, ISwapRouter02} from "../src/interfaces/IUniswap.sol";
import {UniswapV4Venue} from "../src/router/UniswapV4Venue.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Script, console} from "forge-std/Script.sol";

interface IWETH9 {
    function deposit() external payable;
}

/// @notice One real loan on Robinhood Chain mainnet: buy a fraction of a CRWD token through the live Uniswap v4
///         USDG/CRWD pool, post it to StockLender, and borrow USDG against it, priced by CRWD's SlateFeed.
///
///         forge script script/Loan.s.sol --sig "mainnetLoan()" --rpc-url <relay> --private-key $DEPLOYER_PRIVATE_KEY --broadcast
///
///         Env (all optional): LOAN_CRWD (18 dp, default 0.01 CRWD), LOAN_MAX_COST_USDG (6 dp, default 11.5),
///         LOAN_SUPPLY_USDG (6 dp, default 5), LOAN_MAX_WETH (wei, default 0.0075 ETH; only used to top up USDG).
contract Loan is Script {
    address internal constant CRWD = 0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931;
    address internal constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    ISwapRouter02 internal constant ROUTER02 = ISwapRouter02(0xCaf681a66D020601342297493863E78C959E5cb2);
    IPoolManager internal constant POOL_MANAGER = IPoolManager(0x8366a39CC670B4001A1121B8F6A443A643e40951);
    /// @dev The live USDG/CRWD pool: fee 2.945%, tick spacing 295, no hooks.
    uint24 internal constant CRWD_FEE = 29_450;
    int24 internal constant CRWD_TICK_SPACING = 295;

    function mainnetLoan() external {
        require(block.chainid == 4663, "not RH mainnet");
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/../deployments/4663.json"));
        StockLender lender = StockLender(vm.parseJsonAddress(json, ".contracts['StockLender']"));
        uint256 crwdAmount = vm.envOr("LOAN_CRWD", uint256(0.01e18));
        uint256 maxCost = vm.envOr("LOAN_MAX_COST_USDG", uint256(11.5e6));
        uint256 supplyAmount = vm.envOr("LOAN_SUPPLY_USDG", uint256(5e6));
        address me = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        vm.startBroadcast(me);
        // 1. USDG for the purchase and the lender's supply, bought with ETH through the WETH/USDG 0.01% pool if short.
        uint256 need = maxCost + supplyAmount;
        uint256 have = IERC20(USDG).balanceOf(me);
        if (have < need) {
            uint256 maxWeth = vm.envOr("LOAN_MAX_WETH", uint256(0.0075 ether));
            IWETH9(WETH).deposit{value: maxWeth}();
            IERC20(WETH).approve(address(ROUTER02), maxWeth);
            ROUTER02.exactOutputSingle(
                ISwapRouter02.ExactOutputSingleParams({
                    tokenIn: WETH,
                    tokenOut: USDG,
                    fee: 100,
                    recipient: me,
                    amountOut: need - have,
                    amountInMaximum: maxWeth,
                    sqrtPriceLimitX96: 0
                })
            );
        }

        // 2. Exactly `crwdAmount` CRWD from the v4 pool, at most `maxCost` USDG.
        UniswapV4Venue venue = new UniswapV4Venue(POOL_MANAGER);
        IERC20(USDG).approve(address(venue), maxCost);
        uint256 paid =
            venue.swapExactOut(USDG, CRWD, crwdAmount, maxCost, abi.encode(CRWD_FEE, CRWD_TICK_SPACING, address(0)));

        // 3. Supply the loan asset, post the collateral, borrow as much as the lender allows (up to the supply).
        IERC20(USDG).approve(address(lender), supplyAmount);
        lender.supply(supplyAmount);
        IERC20(CRWD).approve(address(lender), crwdAmount);
        lender.deposit(CRWD, crwdAmount);
        (bool ok, uint256 value, uint256 maxBorrow) = lender.quote(CRWD, crwdAmount);
        require(ok, "CRWD's feed is not serving a price");
        uint256 loan = maxBorrow < supplyAmount ? maxBorrow : supplyAmount;
        lender.borrow(CRWD, loan);
        vm.stopBroadcast();

        console.log("venue", address(venue));
        console.log("CRWD bought (18 dp)", crwdAmount);
        console.log("USDG paid for it (6 dp)", paid);
        console.log("collateral value at Slate's price (6 dp)", value);
        console.log("USDG borrowed (6 dp)", loan);
    }
}
