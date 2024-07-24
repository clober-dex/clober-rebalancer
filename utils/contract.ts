import { Address, encodePacked, Hex, keccak256 } from 'viem'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import { getHRE, liveLog } from './misc'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import { ProxyOptions } from 'hardhat-deploy/types'

export const getDeployedAddress = async (name: string): Promise<Address> => {
  const hre = getHRE()
  const deployments = await hre.deployments.get(name)
  return deployments.address as Address
}

export const encodeFeePolicy = (useQuote: boolean, rate: bigint): number => {
  if (rate > 500000n || rate < -500000n) {
    throw new Error('INVALID_RATE')
  }
  const mask = useQuote ? 1n << 23n : 0n
  return Number(mask | (rate + 500000n))
}

export const verify = async (contractAddress: string, args: any[]) => {
  liveLog(`Verifying Contract: ${contractAddress}`)
  try {
    await getHRE().run('verify:verify', {
      address: contractAddress,
      constructorArguments: args,
    })
  } catch (e) {
    console.log(e)
  }
}

export const deployWithVerify = async (
  hre: HardhatRuntimeEnvironment,
  name: string,
  args: any[],
  options?: {
    libraries?: any
    proxy?: boolean | string | ProxyOptions
    contract?: string
  },
) => {
  if (!options) {
    options = {}
  }
  const { deployer } = await hre.getNamedAccounts()
  const deployedAddress = (
    await hre.deployments.deploy(name, {
      from: deployer,
      args: args,
      log: true,
      libraries: options.libraries,
      proxy: options.proxy,
      contract: options.contract,
    })
  ).address

  try {
    await hre.run('verify:verify', {
      address: options.proxy ? await getImplementationAddress(hre.network.provider, deployedAddress) : deployedAddress,
      constructorArguments: args,
    })
  } catch (e) {
    console.log(e)
  }

  return deployedAddress
}
