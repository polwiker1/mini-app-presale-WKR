# WKR Deployment Scripts

Scripts Foundry necesarios para desplegar gobernanza WKR y Presale.

## Reglas Operativas

- Mantener claves privadas y RPC privadas únicamente en `.env` o almacenamiento seguro.
- Simular siempre sin `--broadcast` antes de transmitir.
- Validar owner, balances, direcciones oficiales, oráculo y receptor de fondos.
- En mainnet utilizar una multisig real y el feed oficial Chainlink ETH/USD.

## Gobernanza WKR

Script:

```bash
script/DeployWKRGovernance.s.sol
```

Variables principales:

```bash
PRIVATE_KEY=
MULTISIG_OWNER=
MIN_DELAY_SECONDS=
VOTING_DELAY_BLOCKS=
VOTING_PERIOD_BLOCKS=
PROPOSAL_THRESHOLD_TOKENS=10000
QUORUM_PERCENT=25
```

Simulación:

```bash
forge script script/DeployWKRGovernance.s.sol:DeployWKRGovernance --rpc-url "$RPC_URL"
```

## WKR Presale

Script:

```bash
script/DeployWKRPresale.s.sol
```

El script:

1. Predice la dirección de Presale.
2. Autoriza esa dirección en WKR mediante `setPresaleExempt`.
3. Aprueba y deposita `100,000 WKR`.
4. Despliega la preventa con tres fases.

Variables requeridas:

```bash
PRIVATE_KEY=
RPC_URL=
WKR_ADDRESS=
USDT_ADDRESS=
USDC_ADDRESS=
ETH_USD_FEED=
FUNDS_RECEIVER=
```

Variables opcionales:

```bash
PRESALE_SUPPLY_TOKENS=100000
PRESALE_START_DELAY_SECONDS=3600
PRESALE_PHASE_DURATION=2592000
```

Simulación:

```bash
forge script script/DeployWKRPresale.s.sol:DeployWKRPresale --rpc-url "$RPC_URL"
```

Broadcast:

```bash
forge script script/DeployWKRPresale.s.sol:DeployWKRPresale --rpc-url "$RPC_URL" --broadcast
```

Después del despliegue verificar on-chain:

- Owner y receptor de fondos.
- Feed ETH/USD.
- Inicio, final y duración de cada fase.
- Precios `0.060`, `0.075` y `0.090`.
- `maxSellingAmount = 100,000 WKR`.
- Balance WKR de Presale igual a `100,000 WKR`.
- Presale inicialmente sin ventas.
