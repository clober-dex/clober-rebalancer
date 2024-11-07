import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { deployWithVerify, BOOK_MANAGER, SAFE_WALLET } from '../utils'
import { getChain, isDevelopmentNetwork } from '@nomicfoundation/hardhat-viem/internal/chains'
import { Address } from 'viem'
import { arbitrum, arbitrumSepolia, base } from 'viem/chains'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const chain = await getChain(network.provider)
  const deployer = (await getNamedAccounts())['deployer'] as Address

  if (await deployments.getOrNull('SimpleOracleStrategy')) {
    return
  }

  const rebalancer = await deployments.get('Rebalancer')

  let oracleAddress: Address = '0x'
  let owner: Address = '0x'
  if (chain.id == arbitrumSepolia.id) {
    oracleAddress = (await deployments.get('DatastreamOracle')).address as Address
    owner = deployer
  } else if (chain.id === base.id) {
    oracleAddress = (await deployments.get('DatastreamOracle')).address as Address
    owner = SAFE_WALLET[chain.id] // Safe
  } else {
    throw new Error('Unknown chain')
  }

  const args = [oracleAddress, rebalancer.address, BOOK_MANAGER[chain.id], owner]
  await deployWithVerify(hre, 'SimpleOracleStrategy', args)
}

deployFunction.tags = ['SimpleOracleStrategy']
deployFunction.dependencies = ['Oracle', 'Rebalancer']
export default deployFunction
