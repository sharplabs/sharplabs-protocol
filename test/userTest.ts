import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { RiskOffPool, RiskOffPool__factory, ERC20, Treasury, Treasury__factory} from "../typechain";
import { ERC20Token } from "./utils/tokens";
import {getBigNumber, getERC20ContractFromAddress, impersonateFundErc20} from "./utils/erc20Utils"

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
    let RiskOffPool: RiskOffPool;
    let Treasury: Treasury;
    let owner: SignerWithAddress;
    let _feeTo: SignerWithAddress;
    let _governance: SignerWithAddress;
    let addrs: SignerWithAddress[];
    let USDC: ERC20;
    let _token: ERC20;
    let fsGLP: ERC20;
    let _fee = 300;
    let _gasthreshold = 1;
    let _minimumRequset = 10;
    let _riskOnPoolRatio = 1
    let _startTime = 1600000
    let USDC_WHALE = '0xe8c19db00287e3536075114b2576c70773e039bd'
    let fsGLP_add = '0x1aDDD80E6039594eE970E5872D247bf0414C8903'

    before(async () => {
        // console.info(contract);
        USDC = await getERC20ContractFromAddress(ERC20Token.USDC.address);
        _token = USDC;
        fsGLP = await getERC20ContractFromAddress(fsGLP_add);
        [owner, _feeTo, _governance, ...addrs] = await ethers.getSigners();
        RiskOffPool = await deployContractFromName("RiskOffPool", RiskOffPool__factory);
        await RiskOffPool.deployed();
        Treasury = await deployContractFromName("Treasury", Treasury__factory);
        await Treasury.deployed();
        await Treasury.initialize(_governance.address, RiskOffPool.address, RiskOffPool.address, _riskOnPoolRatio, _startTime)

        await RiskOffPool.initialize(_token.address, _fee, _feeTo.address, _gasthreshold, _minimumRequset, Treasury.address)
        await RiskOffPool.connect(owner).setLockUp(0)
        await Treasury.connect(_governance).updateCapacity(1000000000, 1000000000);
        // Add 500 USDC to the owner address
        await impersonateFundErc20(
            USDC,
            USDC_WHALE,
            owner.address,
            "500.0",
            6
        );
    });

    beforeEach(async () => {

    });

    describe("operate", () => {

        it("user stake", async () => {
            console.info('user stake before info:')
            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let user_balance_wait = await RiskOffPool.balance_wait(owner.address)
            let total_supply_staked = await RiskOffPool.total_supply_staked()
            let total_supply_wait = await RiskOffPool.total_supply_wait()
            let requests = await RiskOffPool.stakeRequest(owner.address)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_wait", user_balance_wait)
            console.info("total_supply_staked", total_supply_staked)
            console.info("total_supply_wait", total_supply_wait)
            console.info("stake queue", requests)

            console.info('user approve...')
            await USDC.approve(RiskOffPool.address, ethers.constants.MaxInt256)
            console.info('user stake...')
            let out = await RiskOffPool.stake(100, {value:100})
            // console.info(out)
            console.info('user stake after info:')
            user_wallet_balance = await USDC.balanceOf(owner.address)
            user_balance_wait = await RiskOffPool.balance_wait(owner.address)
            total_supply_staked = await RiskOffPool.total_supply_staked()
            total_supply_wait = await RiskOffPool.total_supply_wait()
            requests = await RiskOffPool.stakeRequest(owner.address)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_wait", user_balance_wait)
            console.info("total_supply_staked", total_supply_staked)
            console.info("total_supply_wait", total_supply_wait)
            console.info("stake queue", requests)

            console.info('user stake...')
            await RiskOffPool.stake(100, {value:100})
            
            console.info('user stake after info:')
            user_wallet_balance = await USDC.balanceOf(owner.address)
            user_balance_wait = await RiskOffPool.balance_wait(owner.address)
            requests = await RiskOffPool.stakeRequest(owner.address)
            total_supply_staked = await RiskOffPool.total_supply_staked()
            total_supply_wait = await RiskOffPool.total_supply_wait()
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_wait", user_balance_wait)
            console.info("total_supply_staked", total_supply_staked)
            console.info("total_supply_wait", total_supply_wait)
            console.info("stake queue", requests)
        })

        // test if gov can withdraw more then they can 
        it("gov withdrawPoolFunds", async () => {
            let contract_usdc_balance = await USDC.balanceOf(RiskOffPool.address)
            console.info("contract_usdc_balance", contract_usdc_balance)
            console.info("gov withdrawPoolFunds...")
            let out = Treasury.connect(_governance).withdrawPoolFunds(RiskOffPool.address, USDC.address, 100, USDC.address)

            contract_usdc_balance = await USDC.balanceOf(RiskOffPool.address)
            console.info("contract_usdc_balance", contract_usdc_balance)
        })

        // test if gov can withdraw more then they can 
        it("gov withdraw", async () => {
            let treasurt_usdc_balance = await USDC.balanceOf(Treasury.address)
            console.info("treasurt_usdc_balance", treasurt_usdc_balance)
            console.info("gov withdraw...")
            let out = Treasury.connect(_governance).withdraw(USDC.address, 100)

            treasurt_usdc_balance = await USDC.balanceOf(Treasury.address)
            console.info("treasurt_usdc_balance", treasurt_usdc_balance)
        })


        it("gov sendPoolFunds", async () => {
            let contract_usdc_balance = await USDC.balanceOf(RiskOffPool.address)
            console.info("contract_usdc_balance", contract_usdc_balance)
            console.info("gov sendPoolFunds...")
            let out = Treasury.connect(_governance).sendPoolFunds(RiskOffPool.address, USDC.address, 100)

            contract_usdc_balance = await USDC.balanceOf(RiskOffPool.address)
            console.info("contract_usdc_balance", contract_usdc_balance)
        })

        it("gov deposit", async () => {
            let treasurt_usdc_balance = await USDC.balanceOf(Treasury.address)
            console.info("treasurt_usdc_balance", treasurt_usdc_balance)
            console.info("gov deposit...")
            let out = Treasury.connect(_governance).deposit(USDC.address, 100)

            treasurt_usdc_balance = await USDC.balanceOf(Treasury.address)
            console.info("treasurt_usdc_balance", treasurt_usdc_balance)
        })



        it("gov buy glp", async () => {
            console.info('before gov buy glp:')
            let contract_usdc_balance = await USDC.balanceOf(RiskOffPool.address)
            let contract_glp_balance = await fsGLP.balanceOf(RiskOffPool.address)
            console.info("contract_usdc_balance", contract_usdc_balance)
            console.info("contract_glp_balance", contract_glp_balance)
            console.info('gov buy glp ...')
            let out = await Treasury.connect(_governance).buyGLP(RiskOffPool.address, USDC.address, 100, 10, 10)
            // console.info("buy glp", out)
            console.info('after gov buy glp:')
            contract_usdc_balance = await USDC.balanceOf(RiskOffPool.address)
            contract_glp_balance = await fsGLP.balanceOf(RiskOffPool.address)
            console.info("contract_usdc_balance", contract_usdc_balance)
            console.info("contract_glp_balance", contract_glp_balance)
        })

        it("gov sell glp", async () => {
            await ethers.provider.send("evm_increaseTime", [360000])
            await ethers.provider.send("evm_mine", [])
            console.info('before gov sell glp:')
            let contract_usdc_balance = await USDC.balanceOf(RiskOffPool.address)
            let contract_glp_balance = await fsGLP.balanceOf(RiskOffPool.address)
            console.info("contract_usdc_balance", contract_usdc_balance)
            console.info("contract_glp_balance", contract_glp_balance)
            console.info('gov sell glp ...')
            let out = await Treasury.connect(_governance).sellGLP(RiskOffPool.address, USDC.address, contract_glp_balance, 10, _governance.address)
            // console.info("sell glp", out)
            console.info('after gov sell glp:')
            contract_usdc_balance = await USDC.balanceOf(RiskOffPool.address)
            contract_glp_balance = await fsGLP.balanceOf(RiskOffPool.address)
            console.info("contract_usdc_balance", contract_usdc_balance)
            console.info("contract_glp_balance", contract_glp_balance)
        })


        it ("handleStakeRequest", async () => {
            console.info('handleStakeRequest ...')
            let out = await Treasury.connect(_governance).handleStakeRequest(RiskOffPool.address, [owner.address])
            // console.info("handle stake", out)
            let user_balance_wait = await RiskOffPool.balance_wait(owner.address)
            let user_balance_staked = await RiskOffPool.balance_staked(owner.address)
            let requests = await RiskOffPool.stakeRequest(owner.address)
            console.info('after handleStakeRequest info:')
            console.info("user_balance_wait", user_balance_wait)
            console.info("user_balance_staked", user_balance_staked)
            console.info("stake queue", requests)
        })

        // it("user redeem", async () => {
        //     let user_wallet_balance = await USDC.balanceOf(owner.address)
        //     let user_balance_wait = await RiskOffPool.balance_wait(owner.address)
        //     let requests = await RiskOffPool.stakeRequest(owner.address)
        //     console.info("user_wallet_balance", user_wallet_balance)
        //     console.info("user_balance_wait", user_balance_wait)
        //     console.info("stake queue", requests)

        //     let out = await RiskOffPool.redeem()
        //     // console.info(out)

        //     user_wallet_balance = await USDC.balanceOf(owner.address)
        //     user_balance_wait = await RiskOffPool.balance_wait(owner.address)
        //     requests = await RiskOffPool.stakeRequest(owner.address)
        //     console.info("user_wallet_balance", user_wallet_balance)
        //     console.info("user_balance_wait", user_balance_wait)
        //     console.info("stake queue", requests)
        // })

        it("user withdraw request", async () => {
            console.info("before user withdraw request info:")
            let requests = await RiskOffPool.withdrawRequest(owner.address)
            console.info("requests", requests)
            console.info("user submit withdraw request ...")
            let out = await RiskOffPool.withdraw_request(50, {value:100})
            // console.info(out)
            console.info("after user withdraw request info:")
            requests = await RiskOffPool.withdrawRequest(owner.address )
            console.info("requests", requests)
        })

        it("handle withdraw request", async () => {
            console.info("before handle withdraw request:")
            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let requests = await RiskOffPool.withdrawRequest(owner.address)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("requests", requests)
            console.info("handle withdraw request ...")
            let out = await Treasury.connect(_governance).handleWithdrawRequest(RiskOffPool.address, [owner.address])
            // console.info(out)
            console.info("after handle withdraw request:")
            user_wallet_balance = await USDC.balanceOf(owner.address)
            requests = await RiskOffPool.withdrawRequest(owner.address )
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("requests", requests)
        })

        it("gov allocateReward", async () => {
            console.info("before allocateReward")
            let earned = await RiskOffPool.earned(owner.address)
            console.info("user earned", earned)

            console.info("allocateReward ...")
            let out = Treasury.connect(_governance).allocateReward(RiskOffPool.address, 100)

            console.info("after allocateReward")
            earned = await RiskOffPool.earned(owner.address)
            console.info("user earned", earned)
        })


        it("user withdraw", async () => {
            console.info("before user withdraw:")
            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let user_balance_withdraw = await RiskOffPool.balance_withdraw(owner.address)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_withdraw", user_balance_withdraw)
            console.info("user withdraw ...")
            let out = await RiskOffPool.withdraw(30)
            // console.info(out)
            console.info("after user withdraw:")
            user_wallet_balance = await USDC.balanceOf(owner.address)
            user_balance_withdraw = await RiskOffPool.balance_withdraw(owner.address)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_withdraw", user_balance_withdraw)
        })
    });



})