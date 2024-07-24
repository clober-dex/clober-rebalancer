import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { deployWithVerify } from '../../utils'
import { getChain, isDevelopmentNetwork } from '@nomicfoundation/hardhat-viem/internal/chains'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre
  const chain = await getChain(network.provider)

  if (await deployments.getOrNull('MockSwap')) {
    return
  }

  if (!chain.testnet && !isDevelopmentNetwork(chain.id)) {
    return
  }

  await deployWithVerify(hre, 'MockSwap', [])
}

deployFunction.tags = ['mocks']
export default deployFunction
