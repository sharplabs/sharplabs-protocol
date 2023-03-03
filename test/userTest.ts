import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { GLPPOOL, GLPPOOL__factory, ERC20, } from "../typechain";
import { ERC20Token } from "./utils/tokens";
import {getBigNumber, getERC20ContractFromAddress} from "./utils/erc20Utils"

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


describe("sharplabs test", () => {
    let GLP_POOL: GLPPOOL;
    let owner: SignerWithAddress;
    let _feeTo: SignerWithAddress;
    let _governance: SignerWithAddress;
    let _treasury: SignerWithAddress;
    let addrs: SignerWithAddress[];
    let USDC: ERC20;
    let _token: ERC20;
    let _fee = 300

    before(async () => {
        // console.info(contract);
        USDC = await getERC20ContractFromAddress(ERC20Token.USDC.address);
        _token = USDC;
    });

    beforeEach(async () => {
        [owner, _feeTo, _governance, _treasury, ...addrs] = await ethers.getSigners();
        GLP_POOL = await deployContractFromName("GLPPOOL", GLPPOOL__factory, [_token.address, _fee, _feeTo, _governance, _treasury]);
        await GLP_POOL.deployed();
    });

    describe("user operate", () => {
        it("user stake", async () => {
            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let user_balance_wait = await GLP_POOL.balance_wait(owner.address)
            let requests = await GLP_POOL.StakeRequest(owner.address, 1000)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_wait", user_balance_wait)
            console.info("stake queue", requests)

            let out = await GLP_POOL.stake(100)
            console.info(out)

            user_wallet_balance = await USDC.balanceOf(owner.address)
            user_balance_wait = await GLP_POOL.balance_wait(owner.address)
            requests = await GLP_POOL.StakeRequest(owner.address, 1000)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_wait", user_balance_wait)
            console.info("stake queue", requests)
        })

        it("user redeem", async () => {
            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let user_balance_wait = await GLP_POOL.balance_wait(owner.address)
            let requests = await GLP_POOL.StakeRequest(owner.address, 1000)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_wait", user_balance_wait)
            console.info("stake queue", requests)

            let out = await GLP_POOL.redeem()
            console.info(out)

            user_wallet_balance = await USDC.balanceOf(owner.address)
            user_balance_wait = await GLP_POOL.balance_wait(owner.address)
            requests = await GLP_POOL.StakeRequest(owner.address, 1000)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_wait", user_balance_wait)
            console.info("stake queue", requests)
        })

        it("user withdraw request", async () => {
            let requests = await GLP_POOL.WithdrawRequest(owner.address, 1000)
            console.info("requests", requests)

            let out = await GLP_POOL.withdraw_request(100)
            console.info(out)

            requests = await GLP_POOL.WithdrawRequest(owner.address, 1000)
            console.info("requests", requests)
        })


        it("user withdraw", async () => {
            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let user_balance_withdraw = await GLP_POOL.balance_withdraw(owner.address)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_withdraw", user_balance_withdraw)

            let out = await GLP_POOL.withdraw(100)
            console.info(out)
            
            user_wallet_balance = await USDC.balanceOf(owner.address)
            user_balance_withdraw = await GLP_POOL.balance_withdraw(owner.address)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_withdraw", user_balance_withdraw)
        })


        it("user earned", async () => {
            let out = await GLP_POOL.earned(owner.address)
            console.info(out)
        })


    });

})