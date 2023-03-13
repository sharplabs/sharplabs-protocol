import { ethers ,network} from "hardhat";
import { ERC20Mock__factory } from "../../typechain";
import { Contract } from "ethers";

export const getBigNumber = (amount: number, decimals = 18) => {
  return ethers.utils.parseUnits(amount.toString(), decimals);
};

export const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";

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

export const getContractFromAddress = async (
  contractName: string,
  factoryType: any,
  address: string
) => {
  const factory = (await ethers.getContractFactory(
    contractName
  )) as typeof factoryType;
  return factory.attach(address);
};

export const getERC20ContractFromAddress = async (address: string) => {
  const factory = (await ethers.getContractFactory(
    "ERC20Mock"
  )) as ERC20Mock__factory;
  return factory.attach(address);
};

export const fundErc20 = async (
  contract: Contract,
  sender: string,
  recepient: string,
  amount: string,
  decimals: number
) => {
  const FUND_AMOUNT = ethers.utils.parseUnits(amount, decimals);

  // fund erc20 token to the contract
  const MrWhale = await ethers.getSigner(sender);

  const contractSigner = contract.connect(MrWhale);
  await contractSigner.transfer(recepient, FUND_AMOUNT);
};


export const impersonateFundErc20 = async (
  contract: Contract,
  sender: string,
  recepient: string,
  amount: string,
  decimals: number = 18
) => {
  await network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [sender],
  });

  // fund baseToken to the contract
  await fundErc20(contract, sender, recepient, amount, decimals);

  await network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [sender],
  });
};