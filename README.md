# YEET

When all your other yields dry up and dat fixed 20% APY be lookin too JUICY, minimise your depeg risk by using YEET. YEET is a smart vault that manages your risky stablecoin position by automatically liquidating the position into a safe-haven asset (such as USDC) in the event of a possible depegging scenario.

A YEET vault has two important parameters: liquidation threshold and stop-loss. When the mean price of your risky stablecoin across n rounds of the Chainlink price feed dips below the liquidation threshold, the position becomes liquidatable. In this state, anyone can take this entire vault of the risky stablecoin by exchanging safe-haven assets (e.g. USDC) at the rate of the stop-loss. The liquidatoooor keeps any profit resulting from the price delta between the liquidation threshold and the stop-loss.

Protect your stables from depeg risk, put them in a YEET vault today!

## Running Tests

1. Create an `.env` file using the `.env.example` file as a template.
1. Set the environment variables `MAINNET_RPC_URL` and `MAINNET_PK` in `.env`
1. Invoke `yarn test` to run test scenarios located in `./test`
