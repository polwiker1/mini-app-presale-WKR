# WKR Presale Protocol

Contratos, scripts, pruebas y mini dApp para la preventa del token de gobernanza WKR.

El protocolo está diseñado para desplegar una preventa de `100,000 WKR` dividida en tres fases, aceptar pagos con
USDT, USDC y ETH, reservar los tokens comprados y habilitar su reclamo al finalizar la venta.

> Estado: validado en Arbitrum Sepolia. Antes de utilizarlo en mainnet requiere revisión independiente, configuración
> definitiva y simulación contra un fork de Arbitrum One.

## Parámetros WKR

| Regla | Valor |
| --- | ---: |
| Supply inicial WKR | `1,000,000 WKR` |
| Asignación total de preventa | `100,000 WKR` |
| Máximo acumulado por dirección | `10,000 WKR` |
| Compra mínima USDT / USDC | `1 USD` |
| Compra mínima ETH | `0.0001 ETH` |
| Fase 1 | `$0.060 / WKR` |
| Fase 2 | `$0.075 / WKR` |
| Fase 3 | `$0.090 / WKR` |
| Duración predeterminada | `30 días por fase` |

Los cupos son acumulados entre las tres fases. El máximo total de la preventa es `100,000 WKR`, no `100,000 WKR`
por fase.

## Componentes

- `src/WKR.sol`: token ERC20 de gobernanza con votos, permit, burn, límites operativos y handover restringido a DAO.
- `src/WKRGovernor.sol`: gobernanza WKR mediante Governor y Timelock.
- `src/presale.sol`: preventa por fases, compra con stablecoins y ETH, reservas y claim postventa.
- `src/IAggregator.sol`: interfaz mínima compatible con feeds Chainlink.
- `mini-front/`: mini dApp estática para compra, consulta de reserva y claim.
- `script/`: scripts Foundry para despliegue y operaciones de testnet.
- `test/`: pruebas unitarias, de integración, gobernanza, seguridad y fork.

## Seguridad Implementada

- Máximo acumulado de `10,000 WKR` por comprador para stablecoins y ETH.
- Máximo global de `100,000 WKR` entre las tres fases.
- `ReentrancyGuard` en compras con ETH.
- Patrón checks-effects-interactions antes del envío de ETH.
- Precio ETH/USD validado por antigüedad, ronda, valor positivo y decimales.
- Feed ETH/USD reemplazable solamente por el owner.
- Pausa operativa y blacklist.
- Tokens reservados protegidos frente a retiros de emergencia.
- Claim habilitado únicamente después de finalizar la preventa.
- Validación del cronograma de fases durante el despliegue.

## Oráculos

Para Arbitrum One debe utilizarse el feed oficial Chainlink ETH/USD:

```text
0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612
```

En testnet puede utilizarse un oráculo administrado separado. Ese componente no debe incluirse ni reutilizarse en el
despliegue de producción.

## Instalación

```bash
git submodule update --init --recursive
forge build
forge test
```

Los tests fork requieren una RPC de Arbitrum One:

```bash
ARB_RPC_URL=<rpc-arbitrum-one> forge test --match-contract PresaleForkTest -vv
```

Si `ARB_RPC_URL` no está configurada, las pruebas fork se muestran como omitidas.

## Configuración

Crear un archivo local `.env` desde `.env.example`:

```bash
cp .env.example .env
```

Nunca versionar claves privadas, endpoints privados, archivos `.env`, configuraciones runtime del frontend ni
artefactos de broadcast.

La configuración local de la mini dApp se crea desde:

```bash
cp mini-front/config.example.js mini-front/config.js
```

## Despliegue

Simular siempre antes de transmitir:

```bash
forge script script/DeployWKRPresale.s.sol:DeployWKRPresale --rpc-url "$RPC_URL"
```

Transmitir solamente después de validar owner, balances, direcciones oficiales, oráculo, fechas y receptor de fondos:

```bash
forge script script/DeployWKRPresale.s.sol:DeployWKRPresale --rpc-url "$RPC_URL" --broadcast
```

## Checklist Antes de Mainnet

- Ejecutar suite completa y fork tests reales de Arbitrum One.
- Revisar contratos y scripts mediante auditoría independiente.
- Confirmar USDT, USDC y Chainlink ETH/USD oficiales.
- Utilizar multisig real como owner y receptor de fondos.
- Confirmar precios, fechas, cupos y `100,000 WKR` depositados.
- Simular el despliegue completo sin `--broadcast`.
- Verificar contratos en Arbiscan.
- Publicar primero una versión staging de la mini dApp.
- Mantener un procedimiento documentado de pausa, incidentes y cambio de oráculo.

## Reutilización

La arquitectura puede adaptarse a otras preventas mediante contratos y configuraciones independientes. Cada nueva
implementación debe revisar tokenomics, límites, precios, cronograma, oráculo, permisos y requisitos legales antes de
su despliegue.

## Aviso

Este repositorio contiene software experimental. No constituye asesoramiento financiero, legal ni una garantía de
seguridad para producción.
