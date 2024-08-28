    // SPDX-License-Identifier: MIT
    pragma solidity ^0.8.19;

    import "./interfaces/IOptimismMintableERC721.sol";
    import "src/core/interfaces/IHyperCycleLicense.sol";
    import "node_modules/@openzeppelin/contracts/utils/introspection/ERC165.sol";
    import "node_modules/@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
    import "node_modules/@openzeppelin/contracts/access/Ownable.sol";

    contract L2HypercycleLicence is IOptimismMintableERC721, IHyperCycleLicense, ERC721Enumerable, Ownable {

        /* General Errors (modifiers) */
    ///@dev Error for when trying to do a token operation when you're not the owner.
    error MustBeTokenOwner();
    ///@dev Error for when trying to do a token operation when the token is not yet created.
    error MustBeValidToken();

    /* Minting Errors */
    ///@dev Error for when trying to mint beyond the minting limit
    error MintingTooManyTokens();

    /* Splitting Errors */
    ///@dev Error for when trying to split a token beyond height 10.
    error HeightMustBeHigherThanTen();

    /* Merge Errors */
    ///@dev Error for when trying to merge tokens on the odd side.
    error MustBeEvenToken();
    ///@dev Error for when trying to merge root licenses.
    error CantMergeRootLicenses();

    /* getBurnData Errors */
    ///@dev Error for when trying to get the burn data of a non-burnt token
    error TokenMustBeBurnt();

        //Events

        /// @dev   The event when a token is split.
        /// @param owner: The address that split this token.
        /// @param licenseId: The licenseId of the token that was split.
        /// @param newLicenseId1: The licenseId of the token created on the left
        /// @param newLicenseId2: The licenseId of the token created on the right
        event Split(
            address owner,
            uint256 indexed licenseId,
            uint256 newLicenseId1,
            uint256 newLicenseId2
        );

        /// @dev   The event when a token is merged (unsplit).
        /// @param owner: The address that merged this token.
        /// @param parentLicenseId: The licenseId of the token parent that was merged.
        /// @param childLicenseId1: The licenseId of the child token on the left
        /// @param childLicenseId2: The licenseId of the child token on the right
        event Merge(
            address owner,
            uint256 indexed parentLicenseId,
            uint256 childLicenseId1,
            uint256 childLicenseId2
        );

        /// @dev   The event when a token is burnt.
        /// @param owner: The address that burned this token.
        /// @param licenseId: The licenseId of the token that was burnt.
        /// @param burnData: The burn metadata used for this burn.
        event BurnLicense(
            address owner,
            uint256 indexed licenseId,
            string indexed burnData
        );

        address public immutable override BRIDGE;
        address public immutable override REMOTE_TOKEN;
        uint256 public immutable override REMOTE_CHAIN_ID;

        mapping(uint256 => bool) public bridgedTokens;

        string public baseUri;

        error Unauthorised();
        error NotSupported();
        error TokenNotBridged();

        enum Status {NOT_MINTED, MINTED, SPLIT, BURNED}

        struct LicenseNFT {
            Status status;
            uint8 height;
            string burnData;
        }

        mapping(uint256 => LicenseNFT) public tokenData;

        uint256 public constant START_ROOT_TOKEN = 8796629893120;
        uint256 public constant END_ROOT_TOKEN_LIMIT = 8796629893120+4096;
        uint256 public currentRootToken = START_ROOT_TOKEN;




        // sepolia - bridge - 0x4200000000000000000000000000000000000014
        // sepolia - hypercycle licence - 0xa1A874b461056d7dBe6fEB31f2a8c5301A4879Dd
        // sepolia - remote chain id - 0xaa36a7
        constructor(address _bridge, address _remoteToken, uint256 _remoteChainId) ERC721("HypercycleLicence", "HCL"){
            BRIDGE = _bridge;
            REMOTE_TOKEN = _remoteToken;
            REMOTE_CHAIN_ID = _remoteChainId;
        }

        /**
        * @notice Returns the address of the bridge contract.
        * @dev This function returns the address of the bridge contract.
        * @return The address of the bridge contract.
        */
        function bridge() external view returns (address){
            return BRIDGE;
        }

        /**
        * @notice Burns a bridged token.
        * @dev This function burns a bridged token. It can only be called by the bridge contract.
        * @param _from The address of the current owner of the token.
        * @param _tokenId The ID of the token to be burned.
        * @custom:require The caller must be the bridge contract.
        * @custom:require The token must be bridged.
        * @custom:require The caller must be the owner of the token.
        */
        function burn(address _from, uint256 _tokenId) virtual external{
            if(msg.sender != BRIDGE){
                revert Unauthorised();
            }
            if(!bridgedTokens[_tokenId]){
                revert TokenNotBridged();
            }

            if(_from != ownerOf(_tokenId)){
                revert Unauthorised();
            }
            _burn(_tokenId);

            setParentStatus(_tokenId, Status.NOT_MINTED);

            // reset bridge map
            bridgedTokens[_tokenId] = false;
        }

        function remoteChainId() external view returns (uint256){
            return REMOTE_CHAIN_ID;
        }

        function remoteToken() external view returns (address){
            return REMOTE_TOKEN;
        }


        /**
        * @notice Mints a new token.
        * @dev This function mints a new token. It can only be called by the bridge contract.
        * @param _to The address to which the new token will be minted.
        * @param _tokenId The ID of the new token.
        * @custom:require The caller must be the bridge contract.
        * @custom:event Mint Emitted when a new token is minted.
        */
        function safeMint(address _to, uint256 _tokenId) virtual external{
            if(msg.sender != BRIDGE){
                revert Unauthorised();
            }

            _mint(_to, _tokenId);

            tokenData[_tokenId] = LicenseNFT(Status.MINTED, calculateLicenseHeight(_tokenId), "");
            setParentStatus(_tokenId, Status.SPLIT);
            bridgedTokens[_tokenId] = true;

            emit Mint(_to, _tokenId);
        }

        function setParentStatus(uint256 tokenId, Status _status) internal {
            while (tokenId > END_ROOT_TOKEN_LIMIT) {
                tokenId /= 2;
                tokenData[tokenId].status = _status;
            }

        }

        /**
        * @notice Checks if the contract supports a specific interface.
        * @dev This function checks if the contract supports a specific interface.
        * @param interfaceId The interface identifier, as specified in ERC-165.
        * @return True if the contract supports the requested interface, false otherwise.
        */
        function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, IERC165) returns (bool) {
            return
                interfaceId == type(IOptimismMintableERC721).interfaceId ||
                super.supportsInterface(interfaceId);
        }

        // methods from IHyperCycleLicense
        // we cannot mint new tokens on L2, only tokens can be bridged.
        function mint(uint256) external override {
            revert NotSupported();
        }

        /**
        * @notice Splits a license into two new licenses.
        * @dev This function splits a license into two new licenses. The height of the original license must be greater than 10.
        * @param licenseId The ID of the license to be split.
        * @custom:require The caller must be the owner of the license.
        * @custom:require The height of the license must be greater than 10.
        * @custom:event Split Emitted when a license is split.
        */
        function split(uint256 licenseId) external override isOwner(licenseId) {
                    LicenseNFT memory licenseData = tokenData[licenseId];
            if (licenseData.height <= 10) {
                revert HeightMustBeHigherThanTen();
            }

            uint256 licenseId1 = licenseId*2;
            uint256 licenseId2 = licenseId1+1;

            tokenData[licenseId1] = LicenseNFT(Status.MINTED, licenseData.height-1, "");
            tokenData[licenseId2] = LicenseNFT(Status.MINTED, licenseData.height-1, "");
            tokenData[licenseId].status = Status.SPLIT;
            _burn(licenseId);
            _safeMint(msg.sender, licenseId1); 
            _safeMint(msg.sender, licenseId2); 

            emit Split(msg.sender, licenseId, licenseId1, licenseId2);
        }

        /**
        * @notice Returns the total number of tokens in existence.
        * @dev This function is an alias for the `totalSupply` function.
        * @return The total supply of tokens.
        */
        function totalTokens() public view returns (uint256) {
            return totalSupply();
        }


        /**
        * @notice Burns a license and records the burn data.
        * @dev This function burns a license and records the burn data. The caller must be the owner of the license.
        * @param licenseId The ID of the license to be burned.
        * @param burnString The data associated with the burn.
        * @custom:require The caller must be the owner of the license.
        * @custom:event BurnLicense Emitted when a license is burned.
        */
        function burn(uint256 licenseId, string calldata burnString) external override isOwner(licenseId){
            tokenData[licenseId].burnData = burnString;
            tokenData[licenseId].status = Status.BURNED;

            emit BurnLicense(msg.sender, licenseId, burnString);
            _burn(licenseId);
        }

        /**
        * @notice Merges two licenses into their parent license.
        * @dev This function merges two licenses into their parent license. The caller must be the owner of both licenses.
        * @param licenseId The ID of the first license to be merged.
        * @custom:require The caller must be the owner of both licenses.
        * @custom:require The licenseId must be even.
        * @custom:require The parent license must not be a root license.
        * @custom:event Merge Emitted when two licenses are merged.
        */
        function merge(uint256 licenseId) external override isOwner(licenseId) isOwner(licenseId+1) {
            
            if (licenseId%2 != 0) {
                revert MustBeEvenToken();
            } else if (licenseId/2 < START_ROOT_TOKEN) {
                revert CantMergeRootLicenses();
            }
            assert(tokenData[licenseId/2].status == Status.SPLIT);

            tokenData[licenseId].status = Status.NOT_MINTED;
            tokenData[licenseId+1].status = Status.NOT_MINTED;


            _safeMint(msg.sender, licenseId/2);
            _burn(licenseId);
            _burn(licenseId+1);

            emit Merge(msg.sender, licenseId/2, licenseId, licenseId+1);
        }

        /**
        * @notice Retrieves the burn data for a burned license.
        * @dev This function retrieves the burn data for a burned license.
        * @param licenseId The ID of the burned license.
        * @return The burn data associated with the license.
        * @custom:require The license must be in the burned status.
        */
        function getBurnData(uint256 licenseId) external view override returns (string memory) {
            if (tokenData[licenseId].status != Status.BURNED) {
                revert TokenMustBeBurnt();
            }
            return tokenData[licenseId].burnData;
        }

        /**
        * @notice Retrieves the height of a license.
        * @dev This function retrieves the height of a license.
        * @param licenseId The ID of the license.
        * @return The height of the license.
        */
        function getLicenseHeight(uint256 licenseId) external view override returns (uint8) {
            return tokenData[licenseId].height;
        }

        /**
        * @notice Retrieves the status of a license.
        * @dev This function retrieves the status of a license.
        * @param licenseId The ID of the license.
        * @return The status of the license.
        */
        function getLicenseStatus(uint256 licenseId) external view override returns (uint256) {
            return uint256(tokenData[licenseId].status);
        }

        /**
        * @notice Calculates the height of a license.
        * @dev This function calculates the height of a license based on its ID.
        * @param licenseId The ID of the license.
        * @return The calculated height of the license.
        */
        function calculateLicenseHeight(uint256 licenseId) public pure returns (uint8) {
            
            uint256 height;

            while (licenseId > END_ROOT_TOKEN_LIMIT) {
                licenseId /= 2;
                
                unchecked {
                    height++;
                }
            }

            return uint8(19 - height);
        }

        function _baseURI() internal view virtual override returns (string memory) {
            return baseUri;
        }

        function setBaseURI(string memory _baseUri) external onlyOwner {
            baseUri = _baseUri;
        
        }

            modifier isOwner(uint256 licenseId) {
            if (ownerOf(licenseId) != msg.sender) {
                revert MustBeTokenOwner();
            }
            _;
        }
    }
