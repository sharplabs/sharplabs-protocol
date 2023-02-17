import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { Boardroom, Boardroom__factory } from "../typechain";

export const deployContractFromName = async (
    contractName: string,
    factoryType: any,
    args: Array<any> = []
) => {
    const factory = (await ethers.getContractFactory(
        contractName
    )) as typeof factoryType;
    return factory.deploy(...args);
};

export const getBigNumber = (amount: number, decimals = 18) => {
    return ethers.utils.parseUnits(amount.toString(), decimals);
};


describe("Bebu query", () => {
    let GLP_POOL: Boardroom;
    let owner: SignerWithAddress;
    let addr1: SignerWithAddress;
    let addr2: SignerWithAddress;
    let addrs: SignerWithAddress[];

    before(async () => {
        // console.info(contract);
    });

    beforeEach(async () => {
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
        GLP_POOL = await deployContractFromName("GLP_POOL", Boardroom__factory);
        await GLP_POOL.deployed();
    });

    describe("user operate", () => {
        it("tuser stake", async () => {
            let out = await GLP_POOL.stake(100)
            console.info(out)
        })

        it("user withdraw request", async () => {
            let out = await GLP_POOL.withhdraw_request(100)
            console.info(out)
        })


        it("user withdraw", async () => {
            let out = await GLP_POOL.withdraw(100)
            console.info(out)
        })


        it("user claim reward", async () => {
            let out = await GLP_POOL.claimReward()
            console.info(out)
        })



    });

})