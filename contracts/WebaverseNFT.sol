//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
pragma abicoder v2; // required to accept structs as function parameters

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

contract WebaverseNFT is ERC721URIStorage, EIP712 {
    string private constant SIGNING_DOMAIN = "Webaverse-voucher";
    string private constant SIGNATURE_VERSION = "1";
    
    // stores the incrementing nonces for the signers to prevent replay attacks
    mapping(address => uint256) public nonces;
    
    // mapping to store the URIs of all the NFTs
    mapping(uint256 => string) private _tokenURIs;

    constructor()
        ERC721("WebaverseNFT", "WVRS")
        EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {}

    /// @notice Represents an un-minted NFT, which has not yet been recorded into the blockchain. A signed voucher can be redeemed for a real NFT using the redeem function.
    struct NFTVoucher {
        // @notice The id of the token to be redeemed. Must be unique - if another token with this ID already exists, the redeem function will revert.
        uint256 tokenId;
        // @notice The minimum price (in wei) that the NFT creator is willing to accept for the initial sale of this NFT.
        uint256 nonce;
        // @notice The time period for which the voucher is valid
        uint256 expiry;
        // @notice the EIP-712 signature of all other fields in the NFTVoucher struct. For a voucher to be valid, it must be signed by an account with the MINTER_ROLE.
        bytes signature;
    }

    function mint(
        address account,
        uint256 tokenId,
        string memory cid
    ) public {
        _mint(account, tokenId);
        _setURI(tokenId, cid);
    }
    

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), "Query for non existent token");
        return _tokenURIs[tokenId];
        
    }

    /// @notice Redeems an NFTVoucher for an actual NFT, creating it in the process.
    /// @param claimer The address of the account which will receive the NFT upon success.
    /// @param voucher A signed NFTVoucher that describes the NFT to be redeemed.
    function claim(address claimer, NFTVoucher calldata voucher)
        public
        payable
        returns (uint256)
    {
        // make sure signature is valid and get the address of the signer
        address signer = _verify(voucher);

        require(
            signer == ownerOf(voucher.tokenId),
            "Authorization failed: Invalid signature"
        );
        
        require(block.timestamp <= voucher.expiry, "Voucher has already expired");
        
        require(voucher.nonce == nonces[signer], "Invalid nonce value");
        // transfer the token to the claimer
        _transfer(signer, claimer, voucher.tokenId);
        nonces[signer] += 1;
        return voucher.tokenId;
    }

    // Use the mapping _tokenURIs for storing the URIs of NFTs
    function _setURI(uint256 tokenId, string memory cid) internal virtual {
        require(
            _exists(tokenId),
            "Setting URI for non-existent token not allowed"
        );
        require(
            bytes(_tokenURIs[tokenId]).length == 0,
            "This token's URI already exists"
        );
        _tokenURIs[tokenId] = cid;
    }

    /// @notice Returns a hash of the given NFTVoucher, prepared using EIP712 typed data hashing rules.
    /// @param voucher An NFTVoucher to hash.
    function _hash(NFTVoucher calldata voucher)
        internal
        view
        returns (bytes32)
    {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "NFTVoucher(uint256 tokenId,uint256 nonce,uint256 expiry)"
                        ),
                        voucher.tokenId,
                        voucher.nonce,
                        voucher.expiry
                    )
                )
            );
    }

    /// @notice Returns the chain id of the current blockchain.
    /// @dev This is used to workaround an issue with ganache returning different values from the on-chain chainid() function and
    ///  the eth_chainId RPC method. See https://github.com/protocol/nft-website/issues/121 for context.
    function getChainID() external view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    /// @notice Verifies the signature for a given NFTVoucher, returning the address of the signer.
    /// @dev Will revert if the signature is invalid. Does not verify that the signer is authorized to mint NFTs.
    /// @param voucher An NFTVoucher describing an unminted NFT.
    function _verify(NFTVoucher calldata voucher)
        internal
        view
        returns (address)
    {
        bytes32 digest = _hash(voucher);
        return ECDSA.recover(digest, voucher.signature);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721)
        returns (bool)
    {
        return ERC721.supportsInterface(interfaceId);
    }
}