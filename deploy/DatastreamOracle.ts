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
import { arbitrum, arbitrumSepolia, base } from 'viem/chains'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const chain = await getChain(network.provider)
  const deployer = (await getNamedAccounts())['deployer'] as Address

  if (await deployments.getOrNull('DatastreamOracle')) {
    return
  }

  let owner: Address = '0x'
  let datastreamVerifier: Address = '0x'
  if (chain.id === arbitrumSepolia.id) {
    owner = deployer
    datastreamVerifier = '0x2ff010debc1297f19579b4246cad07bd24f2488a'
  } else {
    throw new Error('Unknown chain')
  }

  await deployWithVerify(hre, 'DatastreamOracle', [datastreamVerifier], {
    proxy: {
      proxyContract: 'UUPS',
      execute: {
        methodName: 'initialize',
        args: [owner],
      },
    },
  })
}

deployFunction.tags = ['DatastreamOracle']
export default deployFunction
