import FungibleToken from "../../../contracts/FungibleToken.cdc"
import NonFungibleToken from "../../../contracts/NonFungibleToken.cdc"
import NFTStorefront from "../../../contracts/NFTStorefront.cdc"
import Marketplace from "../../../contracts/Marketplace.cdc"
import FUSD from "../../../contracts/FTs/FUSD.cdc"
import Art from "../../../contracts/NFTs/Versus/Art.cdc"

transaction(listingResourceID: UInt64, storefrontAddress: Address) {
    let paymentVault: @FungibleToken.Vault
    let artCollection: &Art.Collection{NonFungibleToken.Receiver}
    let storefront: &NFTStorefront.Storefront{NFTStorefront.StorefrontPublic}
    let listing: &NFTStorefront.Listing{NFTStorefront.ListingPublic}

    prepare(signer: AuthAccount) {
        // Create a collection to store the purchase if none present
        if signer.borrow<&Art.Collection>(from: Art.CollectionStoragePath) == nil {
            signer.save(<-Art.createEmptyCollection(), to: Art.CollectionStoragePath)
            signer.link<&Art.Collection{Art.CollectionPublic, NonFungibleToken.CollectionPublic}>(
                Art.CollectionPublicPath,
                target: Art.CollectionStoragePath
            )
        }

        self.storefront = getAccount(storefrontAddress)
            .getCapability<&NFTStorefront.Storefront{NFTStorefront.StorefrontPublic}>(NFTStorefront.StorefrontPublicPath)
            .borrow()
            ?? panic("Could not borrow Storefront from provided address")

        self.listing = self.storefront.borrowListing(listingResourceID: listingResourceID)
            ?? panic("No Offer with that ID in Storefront")
        let price = self.listing.getDetails().salePrice

        let fusdVault = signer.borrow<&FUSD.Vault>(from: /storage/fusdVault)
            ?? panic("Cannot borrow FUSD vault from signer storage")
        self.paymentVault <- fusdVault.withdraw(amount: price)

        self.artCollection = signer.borrow<&Art.Collection{NonFungibleToken.Receiver}>(from: Art.CollectionStoragePath)
            ?? panic("Cannot borrow NFT collection receiver from account")
    }

    execute {
        let item <- self.listing.purchase(payment: <-self.paymentVault)

        self.artCollection.deposit(token: <-item)

        // Be kind and recycle
        self.storefront.cleanup(listingResourceID: listingResourceID)
        Marketplace.removeListing(id: listingResourceID)
    }

}
