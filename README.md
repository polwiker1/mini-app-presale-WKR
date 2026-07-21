# WKR Presale Protocol

Contratos, scripts, pruebas y mini dApp para la preventa del token de gobernanza WKR.

El protocolo está diseñado para desplegar una preventa de `100,000 WKR` dividida en tres fases, aceptar pagos con
USDT, USDC y ETH, reservar los tokens comprados y habilitar su reclamo al finalizar la venta.

> Estado: desplegado en Arbitrum One mainnet. Pendiente: verificación pública en Arbiscan, repasada final de UX/legal
> y preparación operativa de liquidez `WKR/USDC`.

## Deploy Arbitrum One

| Componente | Address |
| --- | --- |
| Safe owner / treasury | `0xaA12F41aA983AF84306C443BfB5Ba7a12a3cfdE4` |
| WKR | `0xa9Fe1b986d1352955a6d80b6568Cf4d62E9912CB` |
| Presale | `0xec71bbc7fdd7a39766ea9a80974d4c52498d5de4` |
| TimelockController | `0x85e37E240056D4a3245ECD326Cc02d2A740e0AA2` |
| WKRGovernor | `0x094d06e9ac565d7549300bf6558f61645c3922d1` |
| Chainlink ETH/USD | `0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612` |
| USDC | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` |
| USDT / USDt0 | `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` |

Cronograma productivo:

- Inicio preventa: `2026-08-10 09:00:00` Buenos Aires (`2026-08-10T12:00:00Z`)
- Cierre temporal: `2026-11-08 09:00:00` Buenos Aires (`2026-11-08T12:00:00Z`)

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

Para producción, `PRESALE_OWNER` y `SALE_TOKEN_OWNER` pueden apuntar a una Safe. En ese flujo la Safe prepara
`setPresaleExempt` y `approve` sobre la dirección predicha de la Presale, y una EOA técnica solo ejecuta el deploy.
La Presale queda administrada por la Safe y los `100,000 WKR` salen de la Safe.

Para una fecha publica fija de inicio, configurar `PRESALE_START_TIMESTAMP`. Si se usa el valor operativo previsto
del 10 de agosto de 2026 y fases de 30 dias, el cierre temporal ocurre 90 dias despues, el 8 de noviembre de 2026
a la misma hora de inicio.

Parámetros de gobernanza previstos para producción:

- `PROPOSAL_THRESHOLD_TOKENS=10000`
- `QUORUM_PERCENT=10`
- `VOTING_DELAY_BLOCKS=2419200` (~7 días en Arbitrum)
- `VOTING_PERIOD_BLOCKS=4838400` (~14 días en Arbitrum)
- `MIN_DELAY_SECONDS=172800` (2 días)

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
