import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { deployWithVerify, BOOK_MANAGER, getDeployedAddress, MINTER_ROUTER } from '../utils'
import { getChain } from '@nomicfoundation/hardhat-viem/internal/chains'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre
  const chain = await getChain(network.provider)

  if (await deployments.getOrNull('Minter')) {
    return
  }

  await deployWithVerify(hre, 'Minter', [
    BOOK_MANAGER[chain.id],
    await getDeployedAddress('Rebalancer'),
    MINTER_ROUTER[chain.id],
  ])
}

deployFunction.tags = ['Minter']
deployFunction.dependencies = ['Rebalancer']
export default deployFunction
