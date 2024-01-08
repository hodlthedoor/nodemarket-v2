// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./structs/Order.sol";
import "./structs/Signature.sol";
import "forge-std/console.sol";

/*
 /$$   /$$  /$$$$$$  /$$$$$$$  /$$$$$$$$       /$$      /$$  /$$$$$$  /$$$$$$$  /$$   /$$ /$$$$$$$$ /$$$$$$$$
| $$$ | $$ /$$__  $$| $$__  $$| $$_____/      | $$$    /$$$ /$$__  $$| $$__  $$| $$  /$$/| $$_____/|__  $$__/
| $$$$| $$| $$  \ $$| $$  \ $$| $$            | $$$$  /$$$$| $$  \ $$| $$  \ $$| $$ /$$/ | $$         | $$   
| $$ $$ $$| $$  | $$| $$  | $$| $$$$$         | $$ $$/$$ $$| $$$$$$$$| $$$$$$$/| $$$$$/  | $$$$$      | $$   
| $$  $$$$| $$  | $$| $$  | $$| $$__/         | $$  $$$| $$| $$__  $$| $$__  $$| $$  $$  | $$__/      | $$   
| $$\  $$$| $$  | $$| $$  | $$| $$            | $$\  $ | $$| $$  | $$| $$  \ $$| $$\  $$ | $$         | $$   
| $$ \  $$|  $$$$$$/| $$$$$$$/| $$$$$$$$      | $$ \/  | $$| $$  | $$| $$  | $$| $$ \  $$| $$$$$$$$   | $$   
|__/  \__/ \______/ |_______/ |________/      |__/     |__/|__/  |__/|__/  |__/|__/  \__/|________/   |__/  
*/

/// @title OTC Exchange V2
/// @author hodl.esf.eth
/// @dev Contract for OTC trading of tokens
contract OtcExchange_V2 is AccessControl {
    using SafeERC20 for IERC20;

    // Define roles
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");
    bytes32 public constant TOKEN_ADMIN_ROLE = keccak256("TOKEN_ADMIN_ROLE");

    uint256 public commission = 250; // 2.5%
    address public commissionReceiver;

    address private _ensOwner;

    mapping(address => bool) public signers;

    mapping(bytes32 => bool) public filledOrders;
    mapping(bytes32 => bool) public cancelledOrders;
    mapping(bytes32 => Order) public buyOrdersWithEth;

    mapping(address => uint256) public nonces;
    mapping(address => mapping(uint256 => uint256)) public pairNonces;

    uint256 public totalBalance;

    error OrderFillFailed(Order order);
    error OrderCreateError(Order order);
    error OrderCancelError(Order order);
    error InvalidOrder(Order order);
    error Unauthorised();
    error InvalidArrayLengths();

    event UpdateSigner(address signer, bool isApproved);
    event OnchainBuyOrderCreated(bytes32 indexed orderHash, Order order);
    event OrderFilled(Order order, address signer);
    event OrderCancelled(Order order);
    event NonceIncremented(address indexed user, uint256 newNonce);
    event PairNonceIncremented(
        address indexed user,
        address token1,
        address token2,
        uint256 newNonce
    );

    mapping(address => bool) public paymentTokens;
    mapping(address => bool) public saleTokens;

    /// @notice Initializes roles
    constructor(address _commissionAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(WITHDRAWER_ROLE, msg.sender);
        _grantRole(TOKEN_ADMIN_ROLE, msg.sender);
        commissionReceiver = _commissionAddress;
        _ensOwner = msg.sender;

        // make ETH a valid payment token
        paymentTokens[address(0)] = true;
    }

    function fillOrder(
        Order calldata order,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint8 v2,
        bytes32 r2,
        bytes32 s2,
        address allowedTaker
    ) external payable {
        bytes32 orderHash;

        // if the allowed taker is the zero address then it can be filled by anyone
        if (order.buyer == msg.sender) {
            orderHash = _getEIP712OrderHash(order, allowedTaker, order.seller);
        } else if (order.seller == msg.sender) {
            orderHash = _getEIP712OrderHash(order, order.buyer, allowedTaker);
        } else {
            revert OrderFillFailed(order);
        }

        // Calculate the order hash and check that it has been signed by the gateway
        // this is to prevent front running
        bytes32 orderSignedBySigner = getEIP712OrderHash(order);
        address signer = ecrecover(orderSignedBySigner, v2, r2, s2);

        address maker = ecrecover(orderHash, v, r, s);

        if (
            filledOrders[orderHash] ||
            cancelledOrders[orderHash] ||
            !signers[signer] || // gateway signer
            block.timestamp > order.validUntil ||
            !saleTokens[order.saleToken] ||
            !paymentTokens[order.paymentToken] ||
            order.pairNonce !=
            pairNonces[maker][
                hashTradingPair(order.saleToken, order.paymentToken) // trading pair nonce
            ] ||
            order.nonce != nonces[maker]
        ) {
            revert OrderFillFailed(order);
        }

        // Mark the order as filled
        filledOrders[orderHash] = true;

        if (maker == order.seller && order.buyer == msg.sender) {
            // Current logic for sell orders
            if (!(allowedTaker == address(0) || allowedTaker == order.buyer)) {
                revert OrderFillFailed(order);
            }
            if (order.saleToken == address(0)) {
                if (buyOrdersWithEth[orderHash].amount != order.amount) {
                    revert OrderFillFailed(order);
                }

                // For Ether
                (bool result, ) = order.buyer.call{value: order.amount}("");

                // update the total balance for the
                totalBalance -= order.amount;

                require(result, "Transfer failed");
            } else {
                // Transfer sale token from seller to buyer
                IERC20(order.saleToken).safeTransferFrom(
                    order.seller,
                    order.buyer,
                    order.amount
                );
            }

            // add eth sale token logic here (if order.saleToken == address(0))
            uint256 commissionAmount = getCommission(order.price);

            // Transfer payment from buyer to seller
            if (order.paymentToken == address(0)) {
                if (msg.value != order.price) {
                    revert OrderFillFailed(order);
                }
                // For Ether
                (bool result, ) = order.seller.call{
                    value: order.price - commissionAmount
                }("");
                require(result, "Transfer failed");
            } else {
                // For ERC20 Tokens
                IERC20 paymentToken = IERC20(order.paymentToken);
                paymentToken.safeTransferFrom(
                    order.buyer,
                    order.seller,
                    order.price - commissionAmount
                );
                paymentToken.safeTransferFrom(
                    order.buyer,
                    commissionReceiver,
                    commissionAmount
                );
            }

            emit OrderFilled(order, signer);
        } else if (maker == order.buyer && order.seller == msg.sender) {
            // Logic for buy orders

            if (!(allowedTaker == address(0) || allowedTaker == order.seller)) {
                revert OrderFillFailed(order);
            }

            uint256 commissionAmount = getCommission(order.price);

            if (order.saleToken == address(0)) {
                if (
                    buyOrdersWithEth[orderHash].amount != order.amount ||
                    msg.value != order.amount
                ) {
                    revert OrderFillFailed(order);
                }
                // Transfer sale token from seller to buyer
                (bool result, ) = order.buyer.call{value: order.amount}("");
                require(result, "Transfer failed");
            } else {
                IERC20(order.saleToken).safeTransferFrom(
                    order.seller,
                    order.buyer,
                    order.amount
                );
            }

            if (order.paymentToken == address(0)) {
                // For Ether
                (bool result, ) = order.seller.call{
                    value: order.price - commissionAmount // leave the commission in contract
                }("");

                // update the total balance for the
                totalBalance -= order.price;
                require(result, "Transfer failed");
            } else {
                IERC20 paymentToken = IERC20(order.paymentToken);
                paymentToken.safeTransferFrom(
                    order.buyer,
                    order.seller,
                    order.price - commissionAmount
                );
                paymentToken.safeTransferFrom(
                    order.buyer,
                    commissionReceiver,
                    commissionAmount
                );
            }

            emit OrderFilled(order, signer);
        } else {
            revert Unauthorised();
        }
    }

    function createOrder(
        Order calldata order,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        // Validate order fields

        bytes32 orderHash = getEIP712OrderHash(order);
        if (
            order.amount == 0 ||
            order.price == 0 ||
            order.validUntil <= block.timestamp ||
            buyOrdersWithEth[orderHash].amount != 0
        ) {
            revert OrderCreateError(order);
        }

        if (order.seller == msg.sender && msg.value == order.amount) {
            totalBalance += order.amount;
        } else if (order.buyer == msg.sender && msg.value == order.price) {
            totalBalance += order.price;
        } else {
            revert OrderCreateError(order);
        }

        // Verify signature
        address signer = ecrecover(orderHash, v, r, s);
        if (signer != msg.sender) {
            revert Unauthorised();
        }

        buyOrdersWithEth[orderHash] = order;

        emit OnchainBuyOrderCreated(orderHash, order);
    }

    function cancelOrder(
        Order calldata order,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 orderHash = getEIP712OrderHash(order);

        if (filledOrders[orderHash] || cancelledOrders[orderHash]) {
            revert OrderCancelError(order);
        }

        address signer = ecrecover(orderHash, v, r, s);

        if (
            signer != msg.sender ||
            (signer != order.buyer && signer != order.seller)
        ) {
            revert Unauthorised();
        }

        // optimisticlly cancel to avoid reentrancy
        cancelledOrders[orderHash] = true;

        // check if it's an onchain order with eth and refund the eth if it is.
        if (
            (order.saleToken == address(0) && msg.sender == order.seller) ||
            (order.paymentToken == address(0) && msg.sender == order.buyer)
        ) {
            if (
                order.seller == msg.sender &&
                buyOrdersWithEth[orderHash].amount > 0
            ) {
                totalBalance -= order.amount;
                (bool result, ) = msg.sender.call{value: order.amount}("");
                require(result, "Transfer failed");
            } else if (
                order.buyer == msg.sender &&
                buyOrdersWithEth[orderHash].price > 0
            ) {
                totalBalance -= order.price;
                (bool result, ) = msg.sender.call{value: order.price}("");
                require(result, "Transfer failed");
            } else {
                revert OrderCancelError(order);
            }
        }

        emit OrderCancelled(order);
    }

    function cancelMultipleOrders(
        Order[] calldata orders,
        Signature[] calldata signatures
    ) public {
        if (orders.length != signatures.length) {
            revert InvalidArrayLengths();
        }

        uint256 totalRefund = 0;

        for (uint256 i = 0; i < orders.length; i++) {
            Order calldata order = orders[i];
            Signature calldata signature = signatures[i];

            bytes32 orderHash = getEIP712OrderHash(order);

            if (filledOrders[orderHash] || cancelledOrders[orderHash]) {
                revert OrderCancelError(order);
            }

            address signer = ecrecover(
                orderHash,
                signature.v,
                signature.r,
                signature.s
            );

            if (
                signer != msg.sender ||
                (signer != order.buyer && signer != order.seller)
            ) {
                revert Unauthorised();
            }

            cancelledOrders[orderHash] = true;

            if (
                (order.saleToken == address(0) && msg.sender == order.seller) ||
                (order.paymentToken == address(0) && msg.sender == order.buyer)
            ) {
                if (
                    order.seller == msg.sender &&
                    buyOrdersWithEth[orderHash].amount > 0
                ) {

                    totalRefund += order.amount;
                } else if (
                    order.buyer == msg.sender &&
                    buyOrdersWithEth[orderHash].price > 0
                ) {

                    totalRefund += order.price;
                } else {
                    revert OrderCancelError(order);
                }
            }

            emit OrderCancelled(order);
        }

        totalBalance -= totalRefund; // Update the storage variable at the end

        if (totalRefund > 0) {
            (bool result, ) = msg.sender.call{value: totalRefund}("");
            require(result, "Transfer failed");
        }
    }

    /// @notice Update payment tokens
    /// @dev Only admin can update payment tokens
    function updatePaymentToken(
        address token,
        bool isApproved
    ) external onlyRole(TOKEN_ADMIN_ROLE) {
        paymentTokens[token] = isApproved;
    }

    /// @notice Update sale tokens
    /// @dev Only admin can update sale tokens
    function updateSaleToken(
        address token,
        bool isApproved
    ) external onlyRole(TOKEN_ADMIN_ROLE) {
        saleTokens[token] = isApproved;
    }

    /// @notice Withdraw ETH from contract
    /// @dev Only role with withdrawer permission can withdraw
    function withdraw(
        address payable recipient
    ) external onlyRole(WITHDRAWER_ROLE) {
        // Transfer ETH
        uint256 allowedWithdrawAmount = address(this).balance - totalBalance;
        (bool result, ) = recipient.call{value: allowedWithdrawAmount}("");
        require(result, "Transfer failed");
    }

    /// @notice Withdraw ERC20 tokens from contract
    /// @dev Only role with withdrawer permission can withdraw
    function withdrawToken(
        IERC20 token,
        address recipient,
        uint256 amount
    ) external onlyRole(WITHDRAWER_ROLE) {
        // Transfer Token
        token.safeTransfer(recipient, amount);
    }

    function setCommission(
        uint256 newCommission
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // max 5% commission
        require(newCommission <= 500, "Commission too high");
        commission = newCommission;
    }

    function setCommissionAddress(
        address newCommissionAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newCommissionAddress != address(0), "cannot be zero address");
        commissionReceiver = newCommissionAddress;
    }


    function updateSigner(
        address signer,
        bool isApproved
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        signers[signer] = isApproved;
        emit UpdateSigner(signer, isApproved);
    }

    function updateEnsOwner(
        address newEnsOwner
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _ensOwner = newEnsOwner;
    }

    /// @notice Returns the owner so that the primary address
    /// can be set by this address on the contract
    function owner() external view returns (address) {
        return _ensOwner;
    }

    /// @notice Increments either or both of the order and bid nonces for the msg.sender.
    function incrementNonce(
        Order[] calldata orders,
        Signature[] calldata signatures
    ) external {
        unchecked {
            emit NonceIncremented(msg.sender, ++nonces[msg.sender]);
        }
        cancelMultipleOrders(orders, signatures);
    }

    /// @notice Increments the pair nonce for the msg.sender.
    function incrementPairNonce(
        address token1,
        address token2,
        Order[] calldata orders,
        Signature[] calldata signatures
    ) external {
        uint256 pairKey = hashTradingPair(token1, token2);
        unchecked {
            emit PairNonceIncremented(
                msg.sender,
                token1,
                token2,
                ++pairNonces[msg.sender][pairKey]
            );
        }
        cancelMultipleOrders(orders, signatures);
    }

    function getCommission(
        uint256 orderPrice
    ) public view returns (uint256 commissionAmount) {
        assembly {
            // Load orderPrice from the first stack slot
            let price := orderPrice

            // Load commission rate from storage
            let rate := sload(commission.slot)

            // Multiply price by commission rate
            let grossCommission := mul(price, rate)

            // Divide by 10000 to get the final commission amount
            commissionAmount := div(grossCommission, 10000)
        }
    }

    // Private function for generating the EIP-712 hash
    function _getEIP712OrderHash(
        Order memory order,
        address buyer,
        address seller
    ) private view returns (bytes32) {
        bytes32 typeHash = keccak256(
            "Order(uint128 amount,uint128 price,address seller,uint64 validUntil,uint32 id,address paymentToken,address saleToken,uint64 nonce,address buyer,uint256 pairNonce)"
        );

        // Create the hash using EIP-712 standard
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    getDomainSeparator(),
                    keccak256(
                        abi.encode(
                            typeHash,
                            order.amount,
                            order.price,
                            seller,
                            order.validUntil,
                            order.id,
                            order.paymentToken,
                            order.saleToken,
                            order.nonce,
                            buyer,
                            order.pairNonce
                        )
                    )
                )
            );
    }

    /// @notice Generates the EIP-712 hash of the order
    /// @param order The order to hash
    /// @return hash of the order
    function getEIP712OrderHash(
        Order memory order
    ) public view returns (bytes32) {
        return _getEIP712OrderHash(order, order.buyer, order.seller);
    }

    /// @notice Generates the EIP-712 hash of the order with zero buyer address
    /// @param order The order to hash
    /// @return hash of the order
    function getEIP712OrderHashWithZeroBuyer(
        Order memory order
    ) external view returns (bytes32) {
        return _getEIP712OrderHash(order, address(0), order.seller);
    }

    /// @notice Generates the EIP-712 hash of the order with zero buyer address
    /// @param order The order to hash
    /// @return hash of the order
    function getEIP712OrderHashWithZeroSeller(
        Order memory order
    ) external view returns (bytes32) {
        return _getEIP712OrderHash(order, order.buyer, address(0));
    }

    /// @notice Generates the EIP-712 domain separator
    /// @return EIP-712 domain separator
    function getDomainSeparator() public view returns (bytes32) {
        // EIP-712 domain type hash
        bytes32 domainTypeHash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

        // Values for the domain
        string memory name = "OtcExchange_V2";
        string memory version = "2";
        uint256 chainId = block.chainid;
        address verifyingContract = address(this);

        // Generate the domain separator
        return
            keccak256(
                abi.encode(
                    domainTypeHash,
                    keccak256(bytes(name)),
                    keccak256(bytes(version)),
                    chainId,
                    verifyingContract
                )
            );
    }

    /// @dev I think this is the most efficient way to get a pair key
    /// that works regardless of the order of the addresses
    function hashTradingPair(
        address addr1,
        address addr2
    ) private pure returns (uint256 uniqueKey) {
        assembly {
            // Cast the addresses to uint256 and add them
            uniqueKey := add(addr1, addr2)
        }
    }
}
