import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { RiskOffPool, RiskOffPool__factory, RiskOnPool, RiskOnPool__factory, ERC20, Treasury, Treasury__factory, Sharplabs__factory, Sharplabs } from "../typechain";
import { ERC20Token } from "./utils/tokens";
import { getBigNumber, getERC20ContractFromAddress, impersonateFundErc20 } from "./utils/erc20Utils"
import { BigNumber } from "ethers";

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
    let RiskOnPool: RiskOnPool;
    let Treasury: Treasury;
    let Sharplabs: Sharplabs;
    let owner: SignerWithAddress;
    let _feeTo: string;
    let _governance: SignerWithAddress;
    let addrs: SignerWithAddress[];
    let USDC: ERC20;
    let _token: ERC20;
    let fsGLP: ERC20;
    let _fee = 10;
    let _glpInFee = 40;
    let _glpOutFee = 40;
    let _gasthreshold = getBigNumber(0.0001);
    let _minimumRequset = getBigNumber(1, 6);
    let _riskOnPoolRatio = 10
    let _startTime = 1600000
    let USDC_WHALE = '0x62383739D68Dd0F844103Db8dFb05a7EdED5BBE6'
    let fsGLP_add = '0x1aDDD80E6039594eE970E5872D247bf0414C8903'

    before(async () => {
        [owner, _governance, ...addrs] = await ethers.getSigners();

        USDC = await getERC20ContractFromAddress(ERC20Token.USDC.address);
        _token = USDC;
        fsGLP = await getERC20ContractFromAddress(fsGLP_add);

        RiskOffPool = await deployContractFromName("RiskOffPool", RiskOffPool__factory);
        await RiskOffPool.deployed();
        RiskOnPool = await deployContractFromName("RiskOnPool", RiskOnPool__factory);
        await RiskOnPool.deployed();
        Treasury = await deployContractFromName("Treasury", Treasury__factory);
        await Treasury.deployed();
        Sharplabs = await deployContractFromName("Sharplabs", Sharplabs__factory);
        await Sharplabs.deployed();
        _feeTo = Treasury.address;

        await Treasury.initialize(_token.address, _governance.address, RiskOffPool.address, RiskOnPool.address, _riskOnPoolRatio, _startTime);

        await RiskOffPool.initialize(Sharplabs.address, _token.address, _fee, _feeTo, _glpInFee, _glpOutFee, _gasthreshold, _minimumRequset, Treasury.address)
        await RiskOffPool.setLockUp(0)

        await RiskOnPool.initialize(Sharplabs.address, _token.address, _fee, _feeTo, _glpInFee, _glpOutFee, _gasthreshold, _minimumRequset, Treasury.address)
        await RiskOnPool.setLockUp(0)

        await Treasury.connect(_governance).updateCapacity(getBigNumber(1000, 6), getBigNumber(1000, 6));

        await Sharplabs.initialize(RiskOffPool.address, RiskOnPool.address);

        await impersonateFundErc20(
            USDC,
            USDC_WHALE,
            owner.address,
            "10000.0",
            6
        );
        await impersonateFundErc20(
            USDC,
            USDC_WHALE,
            _governance.address,
            "10000.0",
            6
        );
        await impersonateFundErc20(
            USDC,
            USDC_WHALE,
            Treasury.address,
            "10000.0",
            6
        );
    });

    beforeEach(async () => {

    });


    describe("operate about the RiskOffPool", () => {
        let _pool: RiskOffPool;
        before(async () => {
            _pool = RiskOffPool
        })

        it("user stake", async () => {
            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let user_balance_wait = await _pool.balance_wait(owner.address)
            let total_supply_staked = await _pool.total_supply_staked()
            let total_supply_wait = await _pool.total_supply_wait()
            let requests = await _pool.stakeRequest(owner.address)
            let eth_balance = await ethers.provider.getBalance(_pool.address)
            let stakeAmount = getBigNumber(100, 6)
            let stakeAmountTaxed = stakeAmount.mul(10000 - _fee).div(10000).mul(10000 - _glpInFee).div(10000)

            await USDC.approve(_pool.address, ethers.constants.MaxInt256)
            let out = await _pool.stake(stakeAmount, { value: _gasthreshold})

            expect(user_wallet_balance.sub(stakeAmount)).to.equal(await USDC.balanceOf(owner.address))
            expect(user_balance_wait.add(stakeAmountTaxed)).to.equal(await _pool.balance_wait(owner.address))
            expect(total_supply_staked).to.equal( await _pool.total_supply_staked())
            expect(total_supply_wait.add(stakeAmountTaxed)).to.equal(await _pool.total_supply_wait())
            expect(eth_balance.add(_gasthreshold)).to.equal(await ethers.provider.getBalance(_pool.address))
            expect(requests.amount.add(stakeAmountTaxed)).to.equal((await _pool.stakeRequest(owner.address)).amount)
            expect((await Treasury.epoch()).toBigInt()).to.equal((await _pool.stakeRequest(owner.address)).requestEpoch)

            user_wallet_balance = await USDC.balanceOf(owner.address)
            user_balance_wait = await _pool.balance_wait(owner.address)
            total_supply_staked = await _pool.total_supply_staked()
            total_supply_wait = await _pool.total_supply_wait()
            requests = await _pool.stakeRequest(owner.address)
            eth_balance = await ethers.provider.getBalance(_pool.address)

            stakeAmount = getBigNumber(100, 6);

            await _pool.stake(stakeAmount, { value: _gasthreshold })

            expect(user_wallet_balance.sub(stakeAmount)).to.equal(await USDC.balanceOf(owner.address))
            expect(user_balance_wait.add(stakeAmountTaxed)).to.equal(await _pool.balance_wait(owner.address))
            expect(total_supply_staked).to.equal( await _pool.total_supply_staked())
            expect(total_supply_wait.add(stakeAmountTaxed)).to.equal(await _pool.total_supply_wait())
            expect(eth_balance.add(_gasthreshold)).to.equal(await ethers.provider.getBalance(_pool.address))
            expect(requests.amount.add(stakeAmountTaxed)).to.equal((await _pool.stakeRequest(owner.address)).amount)
            expect((await Treasury.epoch()).toBigInt()).to.equal((await _pool.stakeRequest(owner.address)).requestEpoch)

        })
        // too slow, if you want to test it, switch to true
        if (false) {
            it("gov withdrawPoolFunds: pool -> other", async () => {
                let receiver = owner

                // transfer 100 usdc to pool
                await impersonateFundErc20(
                    USDC,
                    USDC_WHALE,
                    _pool.address,
                    "100.0",
                    6
                );

                let contract_usdc_balance = await USDC.balanceOf(_pool.address)
                let onwer_usdc_balance = await USDC.balanceOf(receiver.address)
                let withdrawAmount = getBigNumber(10, 6)
                let out = await Treasury.connect(_governance).withdrawPoolFunds(_pool.address, USDC.address, withdrawAmount, receiver.address, false)

                expect(contract_usdc_balance.sub(withdrawAmount)).to.equal(await USDC.balanceOf(_pool.address))
                expect(onwer_usdc_balance.add(withdrawAmount)).to.equal(await USDC.balanceOf(receiver.address))
            })
        }

        it("gov withdrawPoolFundsETH: pool -> other", async () => {
            let receiver = owner

            const transactionHash = await owner.sendTransaction({
                to: _pool.address,
                value: getBigNumber(1), // Sends exactly 1.0 ether
                gasLimit: 30000000
              });

            let contract_eth_balance = await ethers.provider.getBalance(_pool.address)
            let onwer_eth_balance = await ethers.provider.getBalance(receiver.address)
            let withdrawAmount = getBigNumber(10, 6)
            let out = await Treasury.connect(_governance).withdrawPoolFundsETH(_pool.address, withdrawAmount, receiver.address)

            expect(contract_eth_balance.sub(withdrawAmount)).to.equal(await ethers.provider.getBalance(_pool.address))
            expect(onwer_eth_balance.add(withdrawAmount)).to.equal(await ethers.provider.getBalance(receiver.address))

            await Treasury.connect(_governance).withdrawPoolFundsETH(_pool.address, 0, receiver.address)
        })


        it("gov withdraw: treasury -> gov", async () => {
            let treasury_usdc_balance = await USDC.balanceOf(Treasury.address)
            let _governance_usdc_balance = await USDC.balanceOf(_governance.address)
            let withdrawAmount = getBigNumber(50, 6)
            let out = await Treasury.connect(_governance).withdraw(USDC.address, withdrawAmount)

            expect(treasury_usdc_balance.sub(withdrawAmount)).to.equal(await USDC.balanceOf(Treasury.address))
            expect(_governance_usdc_balance.add(withdrawAmount)).to.equal( await USDC.balanceOf(_governance.address))

            await Treasury.connect(_governance).withdraw(USDC.address, 0)
        })


        it("gov sendPoolFunds: treasury -> pool", async () => {

            let treasury_usdc_balance = await USDC.balanceOf(Treasury.address)
            let _governance_usdc_balance = await USDC.balanceOf(_governance.address)
            let contract_usdc_balance = await USDC.balanceOf(_pool.address)
            let depositAmount = getBigNumber(100, 6)
            
            let out = await Treasury.connect(_governance).sendPoolFunds(_pool.address, USDC.address, depositAmount)

            expect(contract_usdc_balance.add(depositAmount)).to.equal(await USDC.balanceOf(_pool.address))
            expect(treasury_usdc_balance.sub(depositAmount)).to.equal(await USDC.balanceOf(Treasury.address))
            expect(_governance_usdc_balance).to.equal(await USDC.balanceOf(_governance.address))

            await Treasury.connect(_governance).sendPoolFunds(_pool.address, USDC.address, 0)
        })

        it("gov sendPoolFundsEth: treasury -> pool", async () => {

            const transactionHash = await owner.sendTransaction({
                to: Treasury.address,
                value: getBigNumber(1), // Sends exactly 1.0 ether
                gasLimit: 30000000
              });

            let treasury_eth_balance = await ethers.provider.getBalance(Treasury.address)
            let _governance_eth_balance = await ethers.provider.getBalance(_governance.address)
            let contract_eth_balance = await ethers.provider.getBalance(_pool.address)
            let depositAmount = getBigNumber(100, 6)
            
            let out = await Treasury.connect(_governance).sendPoolFundsETH(_pool.address, depositAmount)

            expect(contract_eth_balance.add(depositAmount)).to.equal(await ethers.provider.getBalance(_pool.address))
            expect(treasury_eth_balance.sub(depositAmount)).to.equal(await ethers.provider.getBalance(Treasury.address))
            // _governance would use the gas

            await Treasury.connect(_governance).sendPoolFundsETH(_pool.address, 0)
        })

        it("gov deposit: gov -> treasury", async () => {
            let _governance_usdc_balance = await USDC.balanceOf(_governance.address)
            let treasury_usdc_balance = await USDC.balanceOf(Treasury.address)
            let depositAmount = getBigNumber(1, 6)
            await USDC.connect(_governance).approve(Treasury.address, ethers.constants.MaxInt256)
            let out = await Treasury.connect(_governance).deposit(USDC.address, depositAmount)

            expect(_governance_usdc_balance.sub(depositAmount)).to.equal(await USDC.balanceOf(_governance.address))
            expect(treasury_usdc_balance.add(depositAmount)).to.equal(await USDC.balanceOf(Treasury.address))
        })

        // too slow, if you want to test it, change it to true
        if (false) {
            it("gov buy glp", async () => {

                console.info('before gov buy glp:')
                let contract_usdc_balance = await USDC.balanceOf(_pool.address)
                let contract_glp_balance = await fsGLP.balanceOf(_pool.address)
                console.info("contract_usdc_balance", contract_usdc_balance)
                console.info("contract_glp_balance", contract_glp_balance)
                console.info('gov buy glp ...')
                let out = await Treasury.connect(_governance).buyGLP(_pool.address, USDC.address, getBigNumber(100, 6), getBigNumber(50, 6), getBigNumber(50, 6))
                console.info('after gov buy glp:')
                contract_usdc_balance = await USDC.balanceOf(_pool.address)
                contract_glp_balance = await fsGLP.balanceOf(_pool.address)
                console.info("contract_usdc_balance", contract_usdc_balance)
                console.info("contract_glp_balance", contract_glp_balance)
            })

            it("gov sell glp", async () => {

                await ethers.provider.send("evm_increaseTime", [360000])
                await ethers.provider.send("evm_mine", [])
                console.info('before gov sell glp:')
                let contract_usdc_balance = await USDC.balanceOf(_pool.address)
                let contract_glp_balance = await fsGLP.balanceOf(_pool.address)
                console.info("contract_usdc_balance", contract_usdc_balance)
                console.info("contract_glp_balance", contract_glp_balance)
                console.info('gov sell glp ...')
                let out = await Treasury.connect(_governance).sellGLP(_pool.address, USDC.address, contract_glp_balance, getBigNumber(10, 6), _governance.address)
                console.info('after gov sell glp:')
                contract_usdc_balance = await USDC.balanceOf(_pool.address)
                contract_glp_balance = await fsGLP.balanceOf(_pool.address)
                console.info("contract_usdc_balance", contract_usdc_balance)
                console.info("contract_glp_balance", contract_glp_balance)
            })
        }


        it("updateEpoch", async () => {
            let epoch = await Treasury.epoch()
            await Treasury.connect(_governance).updateEpoch()
            await Treasury.connect(_governance).updateEpoch()

            expect(epoch.add(2)).to.equal(await Treasury.epoch())
        })


        it("handleStakeRequest", async () => {

            let user_balance_wait = await _pool.balance_wait(owner.address)
            let user_balance_staked = await _pool.balance_staked(owner.address)
            let total_supply_wait = await _pool.total_supply_wait()
            let total_supply_staked = await _pool.total_supply_staked()
            let requests = await _pool.stakeRequest(owner.address)

            let out = await Treasury.connect(_governance).handleStakeRequest(_pool.address, [owner.address])
            expect(0).to.equal(await _pool.balance_wait(owner.address))
            expect(user_balance_wait.sub(requests.amount)).to.equal(await _pool.balance_wait(owner.address))
            expect(user_balance_staked.add(requests.amount)).to.equal(await _pool.balance_staked(owner.address))
            expect(total_supply_staked.add(requests.amount)).to.equal(await _pool.total_supply_staked())
            expect(total_supply_wait.sub(requests.amount)).to.equal(await _pool.total_supply_wait())

        })

        it("user withdraw request", async () => {

            let requests = await _pool.withdrawRequest(owner.address)
            let withdrawAmount = getBigNumber(60, 6)
            let out = await _pool.withdraw_request(withdrawAmount, { value: getBigNumber(0.01) })
            expect((await _pool.withdrawRequest(owner.address)).amount).to.equal(requests.amount.add(withdrawAmount))
        })

        it("updateEpoch", async () => {
            let epoch = await Treasury.epoch()

            await Treasury.connect(_governance).updateEpoch()

            expect(epoch.add(1)).to.equal(await Treasury.epoch())
        })

        it("gov allocateReward", async () => {

            console.info("before allocateReward")
            let earned = await _pool.earned(owner.address)
            console.info("user earned", earned)

            console.info("allocateReward ...")
            let out = await Treasury.connect(_governance).allocateReward(_pool.address, getBigNumber(1, 6))

            console.info("after allocateReward")
            earned = await _pool.earned(owner.address)
            console.info("user earned", earned)
        })

        it("handle withdraw request", async () => {

            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let requests = await _pool.withdrawRequest(owner.address)
            let user_balance_withdraw = await _pool.balance_withdraw(owner.address)
            let realWithdrawAmount = requests.amount.mul(10000 - _glpOutFee).div(10000)
            let out = await Treasury.connect(_governance).handleWithdrawRequest(_pool.address, [owner.address])
            expect(user_wallet_balance).to.equal(await USDC.balanceOf(owner.address))
            expect(0).to.equal((await _pool.withdrawRequest(owner.address)).amount)
            expect(user_balance_withdraw.add(realWithdrawAmount)).to.equal(await _pool.balance_withdraw(owner.address))
            
        });

        it("user withdraw", async () => {

            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let user_balance_withdraw = await _pool.balance_withdraw(owner.address)
            let withdrawAmount = getBigNumber(40, 6)
            let user_balance_reward = await _pool.balance_reward(owner.address)
            
            let out = await _pool.withdraw(withdrawAmount)

            expect(user_wallet_balance.add(withdrawAmount).add(user_balance_reward)).to.equal(await USDC.balanceOf(owner.address))
            expect(await _pool.balance_reward(owner.address)).to.equal(0)
            expect(user_balance_withdraw.sub(withdrawAmount)).to.equal(await _pool.balance_withdraw(owner.address))
        })
    });

    describe("operate about the RiskOnPool", () => {
        let _pool: RiskOnPool;
        before(async () => {
            _pool = RiskOnPool
        })

        it("user stake", async () => {
            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let user_balance_wait = await _pool.balance_wait(owner.address)
            let total_supply_staked = await _pool.total_supply_staked()
            let total_supply_wait = await _pool.total_supply_wait()
            let requests = await _pool.stakeRequest(owner.address)
            let eth_balance = await ethers.provider.getBalance(_pool.address)
            let stakeAmount = getBigNumber(100, 6)
            let stakeAmountTaxed = stakeAmount.mul(10000 - _fee).div(10000).mul(10000 - _glpInFee).div(10000)

            await USDC.approve(_pool.address, ethers.constants.MaxInt256)
            let out = await _pool.stake(stakeAmount, { value: _gasthreshold})

            expect(user_wallet_balance.sub(stakeAmount)).to.equal(await USDC.balanceOf(owner.address))
            expect(user_balance_wait.add(stakeAmountTaxed)).to.equal(await _pool.balance_wait(owner.address))
            expect(total_supply_staked).to.equal( await _pool.total_supply_staked())
            expect(total_supply_wait.add(stakeAmountTaxed)).to.equal(await _pool.total_supply_wait())
            expect(eth_balance.add(_gasthreshold)).to.equal(await ethers.provider.getBalance(_pool.address))
            expect(requests.amount.add(stakeAmountTaxed)).to.equal((await _pool.stakeRequest(owner.address)).amount)
            expect((await Treasury.epoch()).toBigInt()).to.equal((await _pool.stakeRequest(owner.address)).requestEpoch)

            user_wallet_balance = await USDC.balanceOf(owner.address)
            user_balance_wait = await _pool.balance_wait(owner.address)
            total_supply_staked = await _pool.total_supply_staked()
            total_supply_wait = await _pool.total_supply_wait()
            requests = await _pool.stakeRequest(owner.address)
            eth_balance = await ethers.provider.getBalance(_pool.address)

            stakeAmount = getBigNumber(100, 6)

            await _pool.stake(stakeAmount, { value: _gasthreshold })

            expect(user_wallet_balance.sub(stakeAmount)).to.equal(await USDC.balanceOf(owner.address))
            expect(user_balance_wait.add(stakeAmountTaxed)).to.equal(await _pool.balance_wait(owner.address))
            expect(total_supply_staked).to.equal( await _pool.total_supply_staked())
            expect(total_supply_wait.add(stakeAmountTaxed)).to.equal(await _pool.total_supply_wait())
            expect(eth_balance.add(_gasthreshold)).to.equal(await ethers.provider.getBalance(_pool.address))
            expect(requests.amount.add(stakeAmountTaxed)).to.equal((await _pool.stakeRequest(owner.address)).amount)
            expect((await Treasury.epoch()).toBigInt()).to.equal((await _pool.stakeRequest(owner.address)).requestEpoch)

        })
        // too slow, if you want to test it, switch to true
        if (false) {
            it("gov withdrawPoolFunds: pool -> other", async () => {
                let receiver = owner

                // transfer 100 usdc to pool
                await impersonateFundErc20(
                    USDC,
                    USDC_WHALE,
                    _pool.address,
                    "100.0",
                    6
                );

                let contract_usdc_balance = await USDC.balanceOf(_pool.address)
                let onwer_usdc_balance = await USDC.balanceOf(receiver.address)
                let withdrawAmount = getBigNumber(10, 6)
                let out = await Treasury.connect(_governance).withdrawPoolFunds(_pool.address, USDC.address, withdrawAmount, receiver.address, false)

                expect(contract_usdc_balance.sub(withdrawAmount)).to.equal(await USDC.balanceOf(_pool.address))
                expect(onwer_usdc_balance.add(withdrawAmount)).to.equal(await USDC.balanceOf(receiver.address))
            })
        }

        it("gov withdrawPoolFundsETH: pool -> other", async () => {
            let receiver = owner

            const transactionHash = await owner.sendTransaction({
                to: _pool.address,
                value: getBigNumber(1), // Sends exactly 1.0 ether
                gasLimit: 30000000
              });

            let contract_eth_balance = await ethers.provider.getBalance(_pool.address)
            let onwer_eth_balance = await ethers.provider.getBalance(receiver.address)
            let withdrawAmount = getBigNumber(10, 6)
            let out = await Treasury.connect(_governance).withdrawPoolFundsETH(_pool.address, withdrawAmount, receiver.address)

            expect(contract_eth_balance.sub(withdrawAmount)).to.equal(await ethers.provider.getBalance(_pool.address))
            expect(onwer_eth_balance.add(withdrawAmount)).to.equal(await ethers.provider.getBalance(receiver.address))

            await Treasury.connect(_governance).withdrawPoolFundsETH(_pool.address, 0, receiver.address)
        })


        it("gov withdraw: treasury -> gov", async () => {
            let treasury_usdc_balance = await USDC.balanceOf(Treasury.address)
            let _governance_usdc_balance = await USDC.balanceOf(_governance.address)
            let withdrawAmount = getBigNumber(50, 6)
            let out = await Treasury.connect(_governance).withdraw(USDC.address, withdrawAmount)

            expect(treasury_usdc_balance.sub(withdrawAmount)).to.equal(await USDC.balanceOf(Treasury.address))
            expect(_governance_usdc_balance.add(withdrawAmount)).to.equal( await USDC.balanceOf(_governance.address))

            await Treasury.connect(_governance).withdraw(USDC.address, 0)
        })


        it("gov sendPoolFunds: treasury -> pool", async () => {

            let treasury_usdc_balance = await USDC.balanceOf(Treasury.address)
            let _governance_usdc_balance = await USDC.balanceOf(_governance.address)
            let contract_usdc_balance = await USDC.balanceOf(_pool.address)
            let depositAmount = getBigNumber(100, 6)
            
            let out = await Treasury.connect(_governance).sendPoolFunds(_pool.address, USDC.address, depositAmount)

            expect(contract_usdc_balance.add(depositAmount)).to.equal(await USDC.balanceOf(_pool.address))
            expect(treasury_usdc_balance.sub(depositAmount)).to.equal(await USDC.balanceOf(Treasury.address))
            expect(_governance_usdc_balance).to.equal(await USDC.balanceOf(_governance.address))

            await Treasury.connect(_governance).sendPoolFunds(_pool.address, USDC.address, 0)
        })

        it("gov sendPoolFundsEth: treasury -> pool", async () => {

            const transactionHash = await owner.sendTransaction({
                to: Treasury.address,
                value: getBigNumber(1), // Sends exactly 1.0 ether
                gasLimit: 30000000
              });

            let treasury_eth_balance = await ethers.provider.getBalance(Treasury.address)
            let _governance_eth_balance = await ethers.provider.getBalance(_governance.address)
            let contract_eth_balance = await ethers.provider.getBalance(_pool.address)
            let depositAmount = getBigNumber(100, 6)
            
            let out = await Treasury.connect(_governance).sendPoolFundsETH(_pool.address, depositAmount)

            expect(contract_eth_balance.add(depositAmount)).to.equal(await ethers.provider.getBalance(_pool.address))
            expect(treasury_eth_balance.sub(depositAmount)).to.equal(await ethers.provider.getBalance(Treasury.address))
            // _governance would use the gas

            await Treasury.connect(_governance).sendPoolFundsETH(_pool.address, 0)
        })

        it("gov deposit: gov -> treasury", async () => {
            let _governance_usdc_balance = await USDC.balanceOf(_governance.address)
            let treasury_usdc_balance = await USDC.balanceOf(Treasury.address)
            let depositAmount = getBigNumber(1, 6)
            await USDC.connect(_governance).approve(Treasury.address, ethers.constants.MaxInt256)
            let out = await Treasury.connect(_governance).deposit(USDC.address, depositAmount)

            expect(_governance_usdc_balance.sub(depositAmount)).to.equal(await USDC.balanceOf(_governance.address))
            expect(treasury_usdc_balance.add(depositAmount)).to.equal(await USDC.balanceOf(Treasury.address))
        })

        // too slow, if you want to test it, change it to true
        if (false) {
            it("gov buy glp", async () => {

                console.info('before gov buy glp:')
                let contract_usdc_balance = await USDC.balanceOf(_pool.address)
                let contract_glp_balance = await fsGLP.balanceOf(_pool.address)
                console.info("contract_usdc_balance", contract_usdc_balance)
                console.info("contract_glp_balance", contract_glp_balance)
                console.info('gov buy glp ...')
                let out = await Treasury.connect(_governance).buyGLP(_pool.address, USDC.address, getBigNumber(100, 6), getBigNumber(50, 6), getBigNumber(50, 6))
                console.info('after gov buy glp:')
                contract_usdc_balance = await USDC.balanceOf(_pool.address)
                contract_glp_balance = await fsGLP.balanceOf(_pool.address)
                console.info("contract_usdc_balance", contract_usdc_balance)
                console.info("contract_glp_balance", contract_glp_balance)
            })

            it("gov sell glp", async () => {

                await ethers.provider.send("evm_increaseTime", [360000])
                await ethers.provider.send("evm_mine", [])
                console.info('before gov sell glp:')
                let contract_usdc_balance = await USDC.balanceOf(_pool.address)
                let contract_glp_balance = await fsGLP.balanceOf(_pool.address)
                console.info("contract_usdc_balance", contract_usdc_balance)
                console.info("contract_glp_balance", contract_glp_balance)
                console.info('gov sell glp ...')
                let out = await Treasury.connect(_governance).sellGLP(_pool.address, USDC.address, contract_glp_balance, getBigNumber(10, 6), _governance.address)
                console.info('after gov sell glp:')
                contract_usdc_balance = await USDC.balanceOf(_pool.address)
                contract_glp_balance = await fsGLP.balanceOf(_pool.address)
                console.info("contract_usdc_balance", contract_usdc_balance)
                console.info("contract_glp_balance", contract_glp_balance)
            })
        }


        it("updateEpoch", async () => {
            let epoch = await Treasury.epoch()

            await Treasury.connect(_governance).updateEpoch()
            await Treasury.connect(_governance).updateEpoch()

            expect(epoch.add(2)).to.equal(await Treasury.epoch())
        })


        it("handleStakeRequest", async () => {

            let user_balance_wait = await _pool.balance_wait(owner.address)
            let user_balance_staked = await _pool.balance_staked(owner.address)
            let total_supply_wait = await _pool.total_supply_wait()
            let total_supply_staked = await _pool.total_supply_staked()
            let requests = await _pool.stakeRequest(owner.address)

            let out = await Treasury.connect(_governance).handleStakeRequest(_pool.address, [owner.address])
            expect(0).to.equal(await _pool.balance_wait(owner.address))
            expect(user_balance_wait.sub(requests.amount)).to.equal(await _pool.balance_wait(owner.address))
            expect(user_balance_staked.add(requests.amount)).to.equal(await _pool.balance_staked(owner.address))
            expect(total_supply_staked.add(requests.amount)).to.equal(await _pool.total_supply_staked())
            expect(total_supply_wait.sub(requests.amount)).to.equal(await _pool.total_supply_wait())

        })

        it("user withdraw request", async () => {

            let requests = await _pool.withdrawRequest(owner.address)
            let withdrawAmount = getBigNumber(60, 6)
            let out = await _pool.withdraw_request(withdrawAmount, { value: getBigNumber(0.01) })
            expect((await _pool.withdrawRequest(owner.address)).amount).to.equal(requests.amount.add(withdrawAmount))
        })

        it("updateEpoch", async () => {
            let epoch = await Treasury.epoch()

            await Treasury.connect(_governance).updateEpoch()

            expect(epoch.add(1)).to.equal(await Treasury.epoch())
        })

        it("gov allocateReward", async () => {

            console.info("before allocateReward")
            let earned = await _pool.earned(owner.address)
            console.info("user earned", earned)

            console.info("allocateReward ...")
            let out = await Treasury.connect(_governance).allocateReward(_pool.address, getBigNumber(1, 6))

            console.info("after allocateReward")
            earned = await _pool.earned(owner.address)
            console.info("user earned", earned)
        })

        it("handle withdraw request", async () => {

            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let requests = await _pool.withdrawRequest(owner.address)
            let user_balance_withdraw = await _pool.balance_withdraw(owner.address)
            let realWithdrawAmount = requests.amount.mul(10000 - _glpOutFee).div(10000)
            let out = await Treasury.connect(_governance).handleWithdrawRequest(_pool.address, [owner.address])
            expect(user_wallet_balance).to.equal(await USDC.balanceOf(owner.address))
            expect(0).to.equal((await _pool.withdrawRequest(owner.address)).amount)
            expect(user_balance_withdraw.add(realWithdrawAmount)).to.equal(await _pool.balance_withdraw(owner.address))
            
        })

        it("user withdraw", async () => {

            let user_wallet_balance = await USDC.balanceOf(owner.address)
            let user_balance_withdraw = await _pool.balance_withdraw(owner.address)
            let withdrawAmount = getBigNumber(40, 6)
            let user_balance_reward = await _pool.balance_reward(owner.address)
            
            let out = await _pool.withdraw(withdrawAmount)

            expect(user_wallet_balance.add(withdrawAmount).add(user_balance_reward)).to.equal(await USDC.balanceOf(owner.address))
            expect(await _pool.balance_reward(owner.address)).to.equal(0)
            expect(user_balance_withdraw.sub(withdrawAmount)).to.equal(await _pool.balance_withdraw(owner.address))
        })
    })
})
