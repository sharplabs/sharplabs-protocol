accounts.load('0')
accounts.load('1')

// operator = "0xbA32934a66f615Be78D0F874e520e3dCfD94a4b6"
// governance = "0xBABe4f735A7f18611B7A660a7c4D75853d0241bb"

operator = accounts[0]
governance = accounts[1]

OneEther = 1000000000000000000
OneUsdc = 1000000
uint256_max = 115792089237316195423570985008687907853269984665640564039457584007913129639935
usdc = Contract.from_explorer('0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8')
tx_config_operator = {'from':operator,'allow_revert': True}
tx_config_governance = {'from':governance,'allow_revert': True}

riskOffPool = RiskOffPool.deploy(tx_config_operator, publish_source=True)
riskOnPool = RiskOnPool.deploy(tx_config_operator, publish_source=True)
token = Sharplabs.deploy(tx_config_operator, publish_source=True)
treasury = Treasury.deploy(tx_config_operator, publish_source=True)

treasury_start_time = int(input("set treasury start time:"))
token.initialize(riskOffPool, riskOnPool, tx_config_operator)
riskOffPool.initialize(token, 10, treasury, 1e14, 1e7, treasury, tx_config_operator)
riskOnPool.initialize(token, 10, treasury, 1e14, 1e7, treasury, tx_config_operator)
treasury.initialize(governance, riskOffPool, riskOnPool, 10, treasury_start_time, tx_config_operator)
treasury.updateCapacity(1e12, 1e12, tx_config_governance)