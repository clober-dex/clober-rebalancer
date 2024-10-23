import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import {
  deployWithVerify,
  CHAINLINK_SEQUENCER_ORACLE,
  ORACLE_TIMEOUT,
  SEQUENCER_GRACE_PERIOD,
  SAFE_WALLET,
} from '../utils'
import { getChain, isDevelopmentNetwork } from '@nomicfoundation/hardhat-viem/internal/chains'
import { Address } from 'viem'
import {arbitrum, base} from 'viem/chains'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const chain = await getChain(network.provider)
  const deployer = (await getNamedAccounts())['deployer'] as Address

  if (await deployments.getOrNull('ChainlinkOracle')) {
    return
  }

  const chainId = chain.id

  let owner: Address = '0x'
  if (chain.testnet || isDevelopmentNetwork(chainId)) {
    owner = deployer
  } else if (chainId === arbitrum.id || chainId ==base.id) {
    owner = SAFE_WALLET[chainId] // Safe
  } else {
    throw new Error('Unknown chain')
  }

  const args = [CHAINLINK_SEQUENCER_ORACLE[chainId], ORACLE_TIMEOUT[chainId], SEQUENCER_GRACE_PERIOD[chainId], owner]
  await deployWithVerify(hre, 'ChainlinkOracle', args)
}

deployFunction.tags = ['Oracle']
export default deployFunction
