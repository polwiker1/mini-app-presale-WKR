// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title WKR - Wiker Governance Token
 * @notice Token de gobernanza de Portal Wiker.
 * @dev
 * - ERC20 estandar
 * - Soporte de votos on-chain (ERC20Votes)
 * - Quema de tokens (ERC20Burnable)
 * - Compatible con staking, treasury y AMM
 * - Mint controlado por owner (recomendado: multisig o timelock DAO)
 */
contract WKR is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes, Ownable2Step {
    /**
     * @notice Supply inicial fijo: 1,000,000 WKR
     * @dev Como el token usa 18 decimales, se multiplica por 10**18.
     */
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;
    uint256 public constant INITIAL_MAX_TX_AMOUNT = 10_005 * 10 ** 18;
    uint256 public constant INITIAL_MAX_WALLET_AMOUNT = 10_005 * 10 ** 18;
    address public immutable INITIAL_OWNER;
    address public immutable DAO_OWNER;
    uint256 public maxTxAmount;
    uint256 public maxWalletAmount;
    bool public limitsEnabled;
    mapping(address => bool) public isPresaleExempt;
    event LimitsEnabledUpdated(bool oldValue, bool newValue);
    event MaxTxAmountUpdated(uint256 oldValue, uint256 newValue);
    event MaxWalletAmountUpdated(uint256 oldValue, uint256 newValue);
    event PresaleExemptUpdated(address account, bool oldValue, bool newValue);

    /**
     * @param multisigOwner Direccion de la wallet multisig que sera dueña del contrato.
     * @dev
     * - Se configura la multisig como owner desde el deploy.
     * - Se mintea el supply inicial completo a esa multisig.
     */
    constructor(address multisigOwner, address daoOwner)
        ERC20("Wiker Governance", "WKR")
        ERC20Permit("Wiker Governance")
        Ownable(multisigOwner)
    {
        require(multisigOwner != address(0), "Owner zero address");
        require(daoOwner != address(0), "DAO owner zero address");
        require(daoOwner != multisigOwner, "DAO owner must differ from initial owner");
        INITIAL_OWNER = multisigOwner;
        DAO_OWNER = daoOwner;
        maxTxAmount = INITIAL_MAX_TX_AMOUNT;
        maxWalletAmount = INITIAL_MAX_WALLET_AMOUNT;
        limitsEnabled = true;
        _mint(multisigOwner, INITIAL_SUPPLY);
    }

    /**
     * @notice Emision controlada de nuevos tokens.
     * @param to Destinatario de los tokens nuevos.
     * @param amount Cantidad a emitir.
     * @dev Solo la cuenta owner puede ejecutar esta funcion.
     *      Si owner es una multisig o timelock, la aprobacion depende de esa capa de gobernanza.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Mint to zero");
        require(amount > 0, "Mint zero");
        _mint(to, amount);
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        require(newOwner == DAO_OWNER, "Ownership can only move to DAO owner");
        super.transferOwnership(newOwner);
    }

    function setLimitsEnabled(bool enabled) external onlyOwner {
        bool oldValue = limitsEnabled;
        limitsEnabled = enabled;
        emit LimitsEnabledUpdated(oldValue, enabled);
    }

    function setMaxTxAmount(uint256 newMaxTxAmount) external onlyOwner {
        require(newMaxTxAmount > 0, "Max tx zero");
        uint256 oldValue = maxTxAmount;
        maxTxAmount = newMaxTxAmount;
        emit MaxTxAmountUpdated(oldValue, newMaxTxAmount);
    }

    function setMaxWalletAmount(uint256 newMaxWalletAmount) external onlyOwner {
        require(newMaxWalletAmount > 0, "Max wallet zero");
        uint256 oldValue = maxWalletAmount;
        maxWalletAmount = newMaxWalletAmount;
        emit MaxWalletAmountUpdated(oldValue, newMaxWalletAmount);
    }

    function setPresaleExempt(address account, bool exempt) external onlyOwner {
        require(account != address(0), "Presale exempt zero");
        bool oldValue = isPresaleExempt[account];
        isPresaleExempt[account] = exempt;
        emit PresaleExemptUpdated(account, oldValue, exempt);
    }

    /**
     * @notice Hook interno de OZ v5 para transferencias, mint, burn y movimiento de votos.
     * @dev
     * - Se deja override explicito para mantener compatibilidad.
     * - No agrega logica extra; solo llama a la implementacion base.
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        if (limitsEnabled && from != address(0) && to != address(0) && !isPresaleExempt[to]) {
            require(value <= maxTxAmount, "Transfer exceeds max tx");
            require(balanceOf(to) + value <= maxWalletAmount, "Recipient exceeds max wallet");
        }
        super._update(from, to, value);
    }

    /**
     * @notice Nonce actual de una cuenta para firmas EIP-2612 y delegacion.
     * @dev Override requerido por herencia multiple.
     */
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
