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
    let _treasury: SignerWithAddress;
    let addrs: SignerWithAddress[];
    let USDC: ERC20;
    let _token: ERC20;
    let _fee = 300;
    let _gasthreshold = 1;
    let _minimumRequset = 10;
    let _riskOnPoolRatio = 1
    let _startTime = 1600000
    let USDC_WHALE = '0xe8c19db00287e3536075114b2576c70773e039bd'

    before(async () => {
        // console.info(contract);
        USDC = await getERC20ContractFromAddress(ERC20Token.USDC.address);
        _token = USDC;
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

    describe("user operate", () => {
        it("user stake", async () => {
            console.info('user stake before info:')
            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let user_balance_wait = await RiskOffPool.balance_wait(owner.address)
            let requests = await RiskOffPool.stakeRequest(owner.address)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_wait", user_balance_wait)
            console.info("stake queue", requests)

            console.info('user approve...')
            await USDC.approve(RiskOffPool.address, ethers.constants.MaxInt256)
            console.info('user stake...')
            let out = await RiskOffPool.stake(100, {value:100})
            // console.info(out)
            console.info('user stake after info:')
            user_wallet_balance = await USDC.balanceOf(owner.address)
            user_balance_wait = await RiskOffPool.balance_wait(owner.address)
            requests = await RiskOffPool.stakeRequest(owner.address)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_wait", user_balance_wait)
            console.info("stake queue", requests)

            console.info('user stake...')
            await RiskOffPool.stake(100, {value:100})
            
            console.info('user stake after info:')
            user_wallet_balance = await USDC.balanceOf(owner.address)
            user_balance_wait = await RiskOffPool.balance_wait(owner.address)
            requests = await RiskOffPool.stakeRequest(owner.address)
            console.info("user_wallet_balance", user_wallet_balance)
            console.info("user_balance_wait", user_balance_wait)
            console.info("stake queue", requests)
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