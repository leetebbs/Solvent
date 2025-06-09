//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPool, IPoolDataProvider} from "aave-address-book/AaveV3.sol";
import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AggregatorV3Interface} from "@chainlink/src/interfaces/feeds/AggregatorV3Interface.sol";
import {AggregatorInterface} from "aave-v3-core/contracts/dependencies/chainlink/AggregatorInterface.sol";
import {ChainlinkEthereum} from "aave-address-book/ChainlinkEthereum.sol";
import {IPriceOracleGetter} from "aave-v3-core/contracts/interfaces/IPriceOracleGetter.sol";

contract TestAave is Test {
    IERC20 internal testToken;
    IPool internal aavePool;
    IPoolDataProvider internal aaveDataProvider;
    uint256 internal forkId;
    IERC20 internal weth;
    IPriceOracleGetter internal aaveOracle;

    function setUp() public virtual {
        // Fork the Ethereum Mainnet
        forkId = vm.createSelectFork(vm.envString("RPC_MAINNET"));

        // Use a real ERC20 token (e.g., DAI) for testing Aave interactions
        testToken = IERC20(AaveV3EthereumAssets.DAI_UNDERLYING);
        weth = IERC20(AaveV3EthereumAssets.WETH_UNDERLYING);

        // Fund the test contract with some DAI from a well-known whale address
        uint256 daiAmount = 10_000 ether; // 10,000 DAI
        address daiWhale = 0xF977814e90dA44bFA03b6295A0616a897441aceC; // Binance Hot Wallet - a known large DAI holder

        vm.startPrank(daiWhale);
        testToken.transfer(address(this), daiAmount);
        vm.stopPrank();

        // Get the Aave Pool instance
        aavePool = AaveV3Ethereum.POOL;

        // Get the Aave Pool Data Provider instance
        aaveDataProvider = AaveV3Ethereum.AAVE_PROTOCOL_DATA_PROVIDER;
        aaveOracle = IPriceOracleGetter(AaveV3Ethereum.POOL_ADDRESSES_PROVIDER.getPriceOracle());

        console.log("Initial DAI balance of test contract: %s", testToken.balanceOf(address(this)));
        console.log("Initial WETH balance of test contract: %s", weth.balanceOf(address(this)));
    }

    function testSupplyERC20() public {
        uint256 amountToSupply = 100 ether; // 100 DAI

        console.log("\n--- Running testSupplyERC20 ---");
        console.log("Before Supply - User DAI balance: %s", testToken.balanceOf(address(this)));

        // Approve the Aave Pool to spend our DAI tokens
        testToken.approve(address(aavePool), amountToSupply);

        // Supply the DAI tokens to the Aave Pool
        aavePool.supply(address(testToken), amountToSupply, address(this), 0);
        
        console.log("Test for supplying %s. Supplied: %s", IERC20Metadata(address(testToken)).symbol(), amountToSupply);
        console.log("After Supply - User DAI balance: %s", testToken.balanceOf(address(this)));

        (uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor) = aavePool.getUserAccountData(address(this));
        console.log("After Supply - Health Factor: %s", healthFactor);
        console.log("After Supply - Available Borrows ETH: %s", availableBorrowsETH);
    }

    function testBorrowERC20() public {
        // To ensure this test can run independently, call the supply function first
        testSupplyERC20();

        uint256 amountToBorrow = 10 ether; // 10 DAI
        uint256 interestRateMode = 2; // 2 for variable rate, 1 for stable rate

        console.log("\n--- Running testBorrowERC20 ---");
        (uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor) = aavePool.getUserAccountData(address(this));
        console.log("Before Borrow - Health Factor: %s", healthFactor);
        console.log("Before Borrow - Available Borrows ETH: %s", availableBorrowsETH);

        // Borrow the DAI from the Aave Pool
        aavePool.borrow(address(testToken), amountToBorrow, interestRateMode, 0, address(this));

        console.log("Test for borrowing %s token. Borrowed: %s", IERC20Metadata(address(testToken)).symbol(), amountToBorrow);
        (totalCollateralETH, totalDebtETH, availableBorrowsETH, currentLiquidationThreshold, ltv, healthFactor) = aavePool.getUserAccountData(address(this));
        console.log("After Borrow - Health Factor: %s", healthFactor);
        console.log("After Borrow - Available Borrows ETH: %s", availableBorrowsETH);
    }

    function testLiquidate() public {
        console.log("\n--- Running testLiquidate ---");

        // 1. Setup - Supply DAI and Borrow WETH
        uint256 collateralAmount = 10_000 ether; // 10,000 DAI
        uint256 borrowAmount = 1 ether; // 1 WETH

        // Transfer DAI to a new user for liquidation scenario
        address borrower = makeAddr("borrower");
        vm.startPrank(address(this));
        testToken.transfer(borrower, collateralAmount);
        vm.stopPrank();

        vm.startPrank(borrower);
        testToken.approve(address(aavePool), collateralAmount);
        aavePool.supply(address(testToken), collateralAmount, borrower, 0);
        console.log("Borrower supplied %s DAI", collateralAmount);

        aavePool.borrow(address(weth), borrowAmount, 2, 0, borrower);
        console.log("Borrower borrowed %s WETH", borrowAmount);
        vm.stopPrank();

        (uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor) = aavePool.getUserAccountData(borrower);
        console.log("Borrower Health Factor after supply and borrow: %s", healthFactor);
        console.log("Borrower totalCollateralETH: %s", totalCollateralETH);
        console.log("Borrower totalDebtETH: %s", totalDebtETH);
        console.log("Borrower availableBorrowsETH: %s", availableBorrowsETH);

        // Get initial DAI price from Aave Oracle
        uint256 initialDAIPrice = aaveOracle.getAssetPrice(address(testToken));
        console.log("Initial DAI price (from Aave Oracle): %s", initialDAIPrice);

        // 2. Manipulate Price - Lower DAI price or increase WETH price to make health factor < 1
        // We will need to mock Chainlink price feeds here.
        // For example, mock the DAI/USD price to drop significantly.
        // Example: vm.mockCall(DAI_USD_PRICE_FEED_ADDRESS, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(86400, 5e8, 0, 0, 0)); // DAI price drops to $0.5

        // Chainlink price feed addresses
        // address daiUsdPriceFeed = ChainlinkEthereum.DAI_USD;
        // address ethUsdPriceFeed = ChainlinkEthereum.ETH_USD;

        // Mock DAI price to $0.1 (assuming 8 decimals for DAI price feed) directly on AaveOracle
        // For DAI/USD, usually 8 decimals. So $0.1 is 0.1 * 10^8 = 1 * 10^7
        vm.mockCall(
            address(aaveOracle),
            abi.encodeWithSelector(IPriceOracleGetter.getAssetPrice.selector, address(testToken)),
            abi.encode(uint256(1e7))
        );

        (totalCollateralETH, totalDebtETH, availableBorrowsETH, currentLiquidationThreshold, ltv, healthFactor) = aavePool.getUserAccountData(borrower);
        console.log("Borrower Health Factor after price manipulation: %s", healthFactor);
        console.log("Borrower totalCollateralETH after manipulation: %s", totalCollateralETH);
        console.log("Borrower totalDebtETH after manipulation: %s", totalDebtETH);

        // Get DAI price from Aave Oracle after manipulation
        uint256 manipulatedDAIPrice = aaveOracle.getAssetPrice(address(testToken));
        console.log("Manipulated DAI price (from Aave Oracle): %s", manipulatedDAIPrice);

        // 3. Liquidate
        // Find a liquidator (e.g., this contract itself or another address)
        address liquidator = address(this);

        // Get the amount of debt to cover (usually a portion, e.g., 50%)
        // For simplicity, let's try to liquidate the full amount initially, or a significant portion.
        // This requires knowing the aToken (collateral) and debtToken addresses.
        // debtToken is weth, collateral is dai

        // To get the aToken address for DAI, we can use aaveDataProvider.getReserveTokensAddresses(address(testToken))
        (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress) = aaveDataProvider.getReserveTokensAddresses(address(testToken));
        // The amount to liquidate for the principal amount of the debt.
        // The amount of collateral to be liquidated is calculated by Aave based on this and the liquidation bonus.
        uint256 amountToLiquidate = borrowAmount / 2; // Liquidate half of the borrowed WETH

        vm.startPrank(liquidator);
        // The liquidator needs WETH to repay the debt
        deal(address(weth), liquidator, amountToLiquidate);
        weth.approve(address(aavePool), amountToLiquidate);

        // Liquidation call parameters:
        // collateralAsset: The address of the collateral asset (DAI)
        // debtAsset: The address of the debt asset (WETH)
        // user: The address of the user to be liquidated (borrower)
        // debtToCover: The amount of debt to cover, in the debtAsset's decimals
        // receiveAToken: true if the liquidator wants to receive aTokens, false for underlying collateral

        aavePool.liquidationCall(
            address(testToken), // collateralAsset (DAI)
            address(weth),      // debtAsset (WETH)
            borrower,           // user to be liquidated
            amountToLiquidate,  // amount of debt to cover
            true                // receiveAToken (true to receive aDAI, false for DAI)
        );
        vm.stopPrank();

        (totalCollateralETH, totalDebtETH, availableBorrowsETH, currentLiquidationThreshold, ltv, healthFactor) = aavePool.getUserAccountData(borrower);
        console.log("Borrower Health Factor after liquidation: %s", healthFactor);
    }
}