import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { deployWithVerify, BOOK_MANAGER, SAFE_WALLET } from '../utils'
import { getChain, isDevelopmentNetwork } from '@nomicfoundation/hardhat-viem/internal/chains'
import { Address } from 'viem'
import { arbitrum } from 'viem/chains'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const chain = await getChain(network.provider)
  const deployer = (await getNamedAccounts())['deployer'] as Address

  if (await deployments.getOrNull('SimpleOracleStrategy')) {
    return
  }

  const oracle = await deployments.get('Oracle')
  const rebalancer = await deployments.get('Rebalancer')

  let owner: Address = '0x'
  if (chain.testnet || isDevelopmentNetwork(chain.id)) {
    owner = deployer
  } else if (chain.id === arbitrum.id) {
    owner = SAFE_WALLET[chain.id] // Safe
  } else {
    throw new Error('Unknown chain')
  }

  const args = [oracle.address, rebalancer.address, BOOK_MANAGER[chain.id], owner]
  await deployWithVerify(hre, 'SimpleOracleStrategy', args)
}

deployFunction.tags = ['SimpleOracleStrategy']
deployFunction.dependencies = ['Oracle', 'Rebalancer']
export default deployFunction
