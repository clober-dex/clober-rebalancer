import { arbitrum, arbitrumSepolia, base, berachainTestnet } from "viem/chains";
import { Address } from "viem";

export const BOOK_MANAGER: { [chainId: number]: Address } = {
  [arbitrumSepolia.id]: "0xC528b9ED5d56d1D0d3C18A2342954CE1069138a4",
  [base.id]: "0x382CCccbD3b142D7DA063bF68cd0c89634767F76",
  [berachainTestnet.id]: "0x982c57388101D012846aDC4997E9b073F3bC16BD",
};

export const CHAINLINK_SEQUENCER_ORACLE: { [chainId: number]: Address } = {
  [arbitrum.id]: '0xFdB631F5EE196F0ed6FAa767959853A9F217697D',
  [arbitrumSepolia.id]: '0x8B0f27aDf87E037B53eF1AADB96bE629Be37CeA8',
}

export const ORACLE_TIMEOUT: { [chainId: number]: number } = {
  [arbitrum.id]: 24 * 3600,
  [arbitrumSepolia.id]: 24 * 3600,
}

export const SEQUENCER_GRACE_PERIOD: { [chainId: number]: number } = {
  [arbitrum.id]: 3600,
  [arbitrumSepolia.id]: 3600,
}