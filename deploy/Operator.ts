import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { deployWithVerify, getDeployedAddress } from '../utils'
import { getChain, isDevelopmentNetwork } from '@nomicfoundation/hardhat-viem/internal/chains'
import { Address } from 'viem'
import { base } from 'viem/chains'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const chain = await getChain(network.provider)
  const deployer = (await getNamedAccounts())['deployer'] as Address

  if (await deployments.getOrNull('Operator')) {
    return
  }

  let owner: Address = '0x'
  let datastreamOracle
  if (chain.testnet || isDevelopmentNetwork(chain.id)) {
    owner = deployer
  } else if (chain.id === base.id) {
    owner = '0x872251F2C0cC5699c9e0C226371c4D747fDA247f' // bot address
    datastreamOracle = await getDeployedAddress('DatastreamOracle')
  } else {
    throw new Error('Unknown chain')
  }

  await deployWithVerify(hre, 'Operator', [await getDeployedAddress('Rebalancer'), datastreamOracle], {
    proxy: {
      proxyContract: 'UUPS',
      execute: {
        methodName: 'initialize',
        args: [owner],
      },
    },
  })
}

deployFunction.tags = ['Operator']
deployFunction.dependencies = ['Rebalancer', 'Oracle']
export default deployFunction
