import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import {
  deployWithVerify,
  CHAINLINK_SEQUENCER_ORACLE,
  ORACLE_TIMEOUT,
  SEQUENCER_GRACE_PERIOD,
  SAFE_WALLET,
} from '../utils'
import { getChain } from '@nomicfoundation/hardhat-viem/internal/chains'
import { Address } from 'viem'
import { arbitrumSepolia, base } from 'viem/chains'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre
  const chain = await getChain(network.provider)

  if (await deployments.getOrNull('ChainlinkOracle')) {
    return
  }

  let owner: Address = '0x'
  if (chain.id == arbitrumSepolia.id || chain.id == base.id) {
    return
  } else {
    throw new Error('Unknown chain')
  }

  const args = [CHAINLINK_SEQUENCER_ORACLE[chain.id], ORACLE_TIMEOUT[chain.id], SEQUENCER_GRACE_PERIOD[chain.id], owner]
  await deployWithVerify(hre, 'ChainlinkOracle', args)
}

deployFunction.tags = ['Oracle']
export default deployFunction
