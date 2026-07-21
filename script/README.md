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
MIN_DELAY_SECONDS=172800
VOTING_DELAY_BLOCKS=2419200
VOTING_PERIOD_BLOCKS=4838400
PROPOSAL_THRESHOLD_TOKENS=10000
QUORUM_PERCENT=10
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
2. Si el deployer es owner de WKR, autoriza esa dirección mediante `setPresaleExempt` y aprueba `100,000 WKR`.
3. Si WKR está en multisig/Safe, valida que la Safe ya haya autorizado y aprobado la dirección predicha.
4. Despliega la preventa con tres fases, owner administrativo y wallet fondeadora configurables.

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
PRESALE_START_TIMESTAMP=
PRESALE_START_DELAY_SECONDS=3600
PRESALE_PHASE_DURATION=2592000
PRESALE_OWNER=
SALE_TOKEN_OWNER=
```

Para una fecha publica fija, usar `PRESALE_START_TIMESTAMP` con Unix timestamp. Si se deja sin configurar, el
script usa `PRESALE_START_DELAY_SECONDS` y calcula el inicio relativo al bloque del deploy. Con
`PRESALE_PHASE_DURATION=2592000`, la preventa dura 3 fases de 30 dias: 90 dias en total.

Para mainnet con Safe:

- `PRESALE_OWNER` debe ser la Safe que administrará pausa, oráculo y retiros de remanentes.
- `SALE_TOKEN_OWNER` debe ser la Safe que mantiene los `100,000 WKR`.
- Antes del deploy final, la Safe debe ejecutar:
  - `WKR.setPresaleExempt(predictedPresale, true)`.
  - `WKR.approve(predictedPresale, 100000e18)`.
- Luego el deployer técnico puede desplegar `Presale`; los WKR se transfieren desde la Safe y el owner de `Presale` queda en la Safe.

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
