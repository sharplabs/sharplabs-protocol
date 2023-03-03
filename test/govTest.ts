import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { GLPPOOL, GLPPOOL__factory, ERC20, Treasury, Treasury__factory, GLPPOOLHEDGED, GLPPOOLHEDGED__factory} from "../typechain";
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
    let GLPPOOLHEDGED: GLPPOOLHEDGED;
    let Treasury: Treasury;
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
        GLP_POOL = await deployContractFromName("GLPPOOL", GLPPOOL__factory, [_token.address, _fee, _feeTo.address, _governance.address, _treasury]);
        await GLP_POOL.deployed();
        GLPPOOLHEDGED = await deployContractFromName("GLPPOOLHEDGED", GLPPOOLHEDGED__factory, [_token.address, _fee, _feeTo.address, _governance.address, _treasury]);
        await GLPPOOLHEDGED.deployed();
        Treasury = await deployContractFromName("Treasury", Treasury__factory, [_governance.address, GLP_POOL.address, GLPPOOLHEDGED.address])
    });

    describe("gov operate", () => {
        it("gov stake", async () => {
            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let user_balance_wait = await GLP_POOL.balance_wait(owner.address)
            let user_balance_staked = await GLP_POOL.balance_staked(owner.address)
            let requests = await GLP_POOL.StakeRequest(owner.address, 1000)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_wait", user_balance_wait)
            console.info("user_balance_staked", user_balance_staked)
            console.info("stake queue", requests)

            let out = await GLP_POOL.stake(100)
            console.info("stake:", out)
            out = await Treasury.handleStakeRequest(GLP_POOL.address, [owner.address])
            console.info("handle stake", out)

            out = await Treasury.buyGLP(GLP_POOL.address, USDC.address, 120, 100, _governance.address)
            console.info("buy glp", out)

            user_wallet_balance = await USDC.balanceOf(owner.address)
            user_balance_wait = await GLP_POOL.balance_wait(owner.address)
            requests = await GLP_POOL.StakeRequest(owner.address, 1000)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_wait", user_balance_wait)
            console.info("stake queue", requests)
        })

        it("gov handle withdraw request", async () => {
            let requests = await GLP_POOL.WithdrawRequest(owner.address, 1000)
            let withdrawable = await GLP_POOL.balance_withdraw(owner.address)
            console.info("requests", requests)
            console.info("withdrawable", withdrawable)

            let out = await GLP_POOL.withdraw_request(100)
            console.info("withdraw request", out)
            out = await Treasury.handleWithdrawRequest(GLP_POOL.address, [owner.address])
            console.info("handle withdraw request", out)
            out = await Treasury.sellGLP(GLP_POOL.address, USDC.address, 120, 100, _governance.address)
            console.info("sell glp", out)

            requests = await GLP_POOL.WithdrawRequest(owner.address, 1000)
            withdrawable = await GLP_POOL.balance_withdraw(owner.address)
            console.info("requests", requests)
            console.info("withdrawable", withdrawable)
        })

        it("allocateReward", async ()=>{
            let out = await Treasury.allocateReward(GLP_POOL.address, 100)
            console.info(out)
        })


        it("deposit", async ()=>{
            let balance_pool = await USDC.balanceOf(GLP_POOL.address)
            let balance_treasury = await USDC.balanceOf(Treasury.address)
            let balance_governance = await USDC.balanceOf(_governance.address)
            console.info("balance_pool", balance_pool)
            console.info("balance_treasury", balance_treasury)
            console.info("balance_governance", balance_governance)

            let out = await Treasury.deposit(USDC.address, 100)
            console.info(out)

            balance_pool = await USDC.balanceOf(GLP_POOL.address)
            balance_treasury = await USDC.balanceOf(Treasury.address)
            balance_governance = await USDC.balanceOf(_governance.address)
            console.info("balance_pool", balance_pool)
            console.info("balance_treasury", balance_treasury)
            console.info("balance_governance", balance_governance)
        })

        it("withdraw", async ()=>{
            let balance_pool = await USDC.balanceOf(GLP_POOL.address)
            let balance_treasury = await USDC.balanceOf(Treasury.address)
            let balance_governance = await USDC.balanceOf(_governance.address)
            console.info("balance_pool", balance_pool)
            console.info("balance_treasury", balance_treasury)
            console.info("balance_governance", balance_governance)
            
            let out = await Treasury.withdraw(_governance.address, 100)
            console.info(out)

            balance_pool = await USDC.balanceOf(GLP_POOL.address)
            balance_treasury = await USDC.balanceOf(Treasury.address)
            balance_governance = await USDC.balanceOf(_governance.address)
            console.info("balance_pool", balance_pool)
            console.info("balance_treasury", balance_treasury)
            console.info("balance_governance", balance_governance)
        })

        it("withdrawPoolFunds", async ()=>{
            let balance_pool = await USDC.balanceOf(GLP_POOL.address)
            let balance_treasury = await USDC.balanceOf(Treasury.address)
            let balance_governance = await USDC.balanceOf(_governance.address)
            console.info("balance_pool", balance_pool)
            console.info("balance_treasury", balance_treasury)
            console.info("balance_governance", balance_governance)

            let out = await Treasury.withdrawPoolFunds(GLP_POOL.address, USDC.address, 100)
            console.info(out)

            balance_pool = await USDC.balanceOf(GLP_POOL.address)
            balance_treasury = await USDC.balanceOf(Treasury.address)
            balance_governance = await USDC.balanceOf(_governance.address)
            console.info("balance_pool", balance_pool)
            console.info("balance_treasury", balance_treasury)
            console.info("balance_governance", balance_governance)
        })

    });

})