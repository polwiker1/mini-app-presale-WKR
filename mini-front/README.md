# Wiker Preventa (Presale) Mini Front

Mini dApp estática para compra de WKR con MetaMask como opción principal y WalletConnect opcional.

Incluye compra, reserva visible y reclamo de WKR cuando finaliza la preventa.

## Uso

1. Crear `config.js` local desde `config.example.js`.
2. Configurar direcciones y `walletConnectProjectId` en `config.js`.
2. Abrir `index.html` en el navegador.
3. Conectar MetaMask en Arbitrum Sepolia.
4. Comprar WKR y revisar `Tu reserva`.
5. Usar `Reclamar WKR` cuando el reclamo esté abierto.

## Nota

El contrato de preventa debe estar autorizado en `WKR` con `setPresaleExempt(presaleAddress, true)` antes de fondear los `100,000 WKR`.

`config.js` esta ignorado por Git para no versionar direcciones temporales ni el projectId de Reown. En Vercel conviene generarlo desde variables de entorno durante el build/deploy.
