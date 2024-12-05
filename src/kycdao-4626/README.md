# KYC'ed ERC-4626 

A KYCDao NFT allows gated access into a new 4626 pool of a given ERC20 asset

Main implementation here is around the hasKYC modifier which gates access to all main 4626 functions.
Serves as an example to provide gated access to a pool.

## About KYCDAO

The kycDAO platform, which can be accessed at https://kycdao.xyz/, represents a compliance framework that has been natively built for web3 applications. Its primary purpose is to facilitate the use of compliant smart contracts. 

In the context of this project, the kycDAO smart contracts [dynamic soulbound NFTs] have been employed to implement a gating mechanism. This mechanism restricts access to the vault to a select group of individuals who are recognized as `trusted anons` within the kycDAO community. `Trusted anons` are compliant. `Trusted anons` are compliant users of the web3 space. 

To learn more about kycDAO's compliance framework : https://docs.kycdao.xyz/

If you are interested to integrate kycDAO: https://docs.kycdao.xyz/quickstart/ [Widget to onboard users; smart contracts to gate]
