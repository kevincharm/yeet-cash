import { expect } from 'chai'
import { ethers } from 'hardhat'
import {
    MockV3Aggregator__factory,
    USDX__factory,
    USDC__factory,
    YeetVault__factory,
} from '../typechain'

const { BigNumber } = ethers

describe('Yeet Vault', () => {
    /**
     * This is a simple scenario simulating a depeg event for an imaginary stablecoin "USDX",
     * and the safe-haven asset set as (a mock implementation of) USDC.
     */
    it('should run simple scenario', async () => {
        const [deployer, depositooor, liquidatooor] = await ethers.getSigners()
        const mockUsdxPriceFeed = await new MockV3Aggregator__factory(deployer).deploy(
            8,
            100_000_000
        )
        const usdx = await new USDX__factory(deployer).deploy()
        const usdc = await new USDC__factory(deployer).deploy() // Mock USDC
        const yeetUsdx = await new YeetVault__factory(deployer).deploy(
            'Yeet Vault: USDX',
            'yeetUSDX',
            usdx.address,
            usdc.address,
            5 /** number of rounds of the Chainlink price feed to calculate mean price over */,
            97_000_000 /** 0.97 liquidation threshold in 8dp (chainlink aggregator precision) */,
            95_000_000 /** 0.95 stop-loss threshold in 8dp (chainlink aggregator precision) */,
            mockUsdxPriceFeed.address
        )

        // Mint 100k USDX to depositooor.
        const usdxAmountToDeposit = ethers.utils.parseEther('100000')
        await usdx.mint(depositooor.address, usdxAmountToDeposit)
        // Deposit 100k USDX to Yeet Vault!
        await usdx.connect(depositooor).approve(yeetUsdx.address, usdxAmountToDeposit)
        await yeetUsdx.connect(depositooor)['deposit(uint256)'](usdxAmountToDeposit)
        // In the beginning, USDX:yeetUSDX redemption rate should be 1:1
        expect(await yeetUsdx.balanceOf(depositooor.address)).to.equal(usdxAmountToDeposit)

        // Simulate depeg of our deposited USDX to .95 (below threshold of .97) by
        // posting low prices for 10 rounds to the mock Chainlink price feed.
        for (let i = 0; i < 10; i++) {
            await mockUsdxPriceFeed.updateAnswer(95_000_000)
        }
        // At this point, the protocol should open liquidations and a Keeper will
        // trigger the state of the vault to "Liquidatable"
        const [isLiquidatable, meanPrice] = await yeetUsdx.isLiquidatable()
        expect(isLiquidatable).to.equal(true)
        expect(meanPrice).to.equal(95_000_000)
        // Simulate a Keeper performing upkeep.
        await yeetUsdx.performUpkeep('0x00')

        const allUsdxInVault = await usdx.balanceOf(yeetUsdx.address)
        // Execute a liquidation. IRL this would be performed by any searcher that can
        // find a better deal for USDX/USDC than the stop-loss specified in this contract (.95)
        const usdcToOffer = BigNumber.from('95000').mul(1e6)
        // Mint some USDC first. IRL, the liquidatooor would probably use a flashloan.
        await usdc.mint(liquidatooor.address, usdcToOffer)
        // Offer the USDC at stop-loss rate as liquidation.
        await usdc.connect(liquidatooor).approve(yeetUsdx.address, usdcToOffer)
        await yeetUsdx.connect(liquidatooor).yeet(usdcToOffer)
        // Protocol gives the liquidatooor all the USDX.
        expect(await usdx.balanceOf(liquidatooor.address)).to.equal(allUsdxInVault)
    })
})
