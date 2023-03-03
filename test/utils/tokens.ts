export interface IToken {
    symbol: string;
    name: string;
    decimals: number;
    address: string;
  }
  
  type erc20Token = { [erc20: string]: IToken };
  
  export const ERC20Token: erc20Token = {
    ETH: {
      symbol: "ETH",
      name: "ETH",
      decimals: 18,
      address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    },
    WETH: {
        symbol: "WETH",
        name: "WETH",
        decimals: 18,
        address: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
      },
    USDC: {
      symbol: "USDC",
      name: "USD Coin",
      decimals: 6,
      address: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
    },
  };
  