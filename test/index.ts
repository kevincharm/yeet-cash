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
    it('should run simple scenario', async () => {
        const [deployer] = await ethers.getSigners()
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
            5,
            97_000_000 /** 0.97 liquidation threshold */,
            95_000_000 /** 0.95 stop-loss */,
            mockUsdxPriceFeed.address
        )

        // Mint 100k USDX to self
        const usdxAmountToDeposit = ethers.utils.parseEther('100000')
        await usdx.mint(deployer.address, usdxAmountToDeposit)
        // Deposit 100k USDX to Yeet Vault
        await usdx.approve(yeetUsdx.address, usdxAmountToDeposit)
        await yeetUsdx['deposit(uint256)'](usdxAmountToDeposit)
        // In the beginning, USDX:yeetUSDX redemption rate should be 1:1
        expect(await yeetUsdx.balanceOf(deployer.address)).to.equal(usdxAmountToDeposit)

        // Simulate depeg to .95 (below threshold of .97)
        for (let i = 0; i < 10; i++) {
            await mockUsdxPriceFeed.updateAnswer(95_000_000)
        }
        const [isLiquidatable, meanPrice] = await yeetUsdx.isLiquidatable()
        expect(isLiquidatable).to.equal(true)
        expect(meanPrice).to.equal(95_000_000)

        // Simulate a Keeper performing upkeep
        await yeetUsdx.performUpkeep('0x00')

        // Liquidate
        const usdcToOffer = BigNumber.from('95000').mul(1e6)
        // Mint some USDC first
        await usdc.mint(deployer.address, usdcToOffer)
        // Offer the USDC at stop-loss rate as liquidation
        await usdc.approve(yeetUsdx.address, usdcToOffer)
        await yeetUsdx.yeet(usdcToOffer)
    })
})
