const DEFAULT_CONFIG = {
  chainId: 421614,
  chainHex: "0x66eee",
  chainName: "Arbitrum Sepolia",
  rpcUrl: "https://sepolia-rollup.arbitrum.io/rpc",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  blockExplorerUrl: "https://sepolia.arbiscan.io",
  presaleAddress: "0x0000000000000000000000000000000000000000",
  wkrAddress: "0x0000000000000000000000000000000000000000",
  usdtAddress: "0x0000000000000000000000000000000000000000",
  usdcAddress: "0x0000000000000000000000000000000000000000",
  walletConnectProjectId: "",
  minPurchase: "1",
};

const CONFIG = { ...DEFAULT_CONFIG, ...(window.WIKER_CONFIG || {}) };
const MAX_PRESALE_PER_WALLET = 10_000n * 10n ** 18n;
const MIN_ETH_PURCHASE = 100_000_000_000_000n;

const PRESALE_ABI = [
  { name: "buyWithStable", type: "function", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [] },
  { name: "buyWithEth", type: "function", stateMutability: "payable", inputs: [], outputs: [] },
  { name: "claim", type: "function", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { name: "getEtherPrice", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "currentPhase", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "phases", type: "function", stateMutability: "view", inputs: [{ type: "uint256" }, { type: "uint256" }], outputs: [{ type: "uint256" }] },
  { name: "totalSold", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "maxSellingAmount", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "userTokenBalance", type: "function", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { name: "startingTime", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "endingTime", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "paused", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
];

const ERC20_ABI = [
  { name: "approve", type: "function", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }] },
  { name: "allowance", type: "function", stateMutability: "view", inputs: [{ type: "address" }, { type: "address" }], outputs: [{ type: "uint256" }] },
  { name: "balanceOf", type: "function", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { name: "decimals", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
];

const state = {
  provider: null,
  account: null,
  phase: 0n,
  phaseEndTimes: [0n, 0n, 0n],
  priceUsd6: 0n,
  maxSellingAmount: 0n,
  totalSold: 0n,
  reserved: 0n,
  ethPriceUsd18: 0n,
  startingTime: 0n,
  endingTime: 0n,
  decimals: { USDT: 6, USDC: 6, ETH: 18, WKR: 18 },
};

const elements = {
  connectMetaMask: document.querySelector("#connectMetaMask"),
  connectWalletConnect: document.querySelector("#connectWalletConnect"),
  statusMessage: document.querySelector("#statusMessage"),
  paymentToken: document.querySelector("#paymentToken"),
  payAmount: document.querySelector("#payAmount"),
  wkrQuote: document.querySelector("#wkrQuote"),
  approveButton: document.querySelector("#approveButton"),
  buyButton: document.querySelector("#buyButton"),
  claimButton: document.querySelector("#claimButton"),
  claimStatusLabel: document.querySelector("#claimStatusLabel"),
  phaseLabel: document.querySelector("#phaseLabel"),
  priceLabel: document.querySelector("#priceLabel"),
  remainingLabel: document.querySelector("#remainingLabel"),
  reservedLabel: document.querySelector("#reservedLabel"),
  timeLabel: document.querySelector("#timeLabel"),
  networkLabel: document.querySelector("#networkLabel"),
};

elements.connectMetaMask.addEventListener("click", () => runAction(connectMetaMask));
elements.connectWalletConnect.addEventListener("click", () => runAction(connectWalletConnect));
elements.paymentToken.addEventListener("change", handlePaymentTokenChange);
elements.payAmount.addEventListener("input", refreshQuote);
elements.approveButton.addEventListener("click", () => runAction(approveStable));
elements.buyButton.addEventListener("click", () => runAction(buyWkr));
elements.claimButton.addEventListener("click", () => runAction(claimWkr));

if (window.ethereum) {
  window.ethereum.on("accountsChanged", () => runAction(connectMetaMask));
  window.ethereum.on("chainChanged", () => window.location.reload());
}

refreshUi();
setInterval(refreshUi, 30_000);

async function connectMetaMask() {
  if (!window.ethereum) {
    setStatus("No encontré MetaMask. Instalá MetaMask o abrí esta página desde MetaMask Mobile.", "error");
    return;
  }

  state.provider = window.ethereum;
  const accounts = await state.provider.request({ method: "eth_requestAccounts" });
  state.account = accounts[0];
  await ensureNetwork();
  setStatus(`Wallet conectada: ${shortAddress(state.account)}`, "ok");
  await loadOnChainState();
}

async function connectWalletConnect() {
  if (!CONFIG.walletConnectProjectId) {
    setStatus("WalletConnect requiere configurar walletConnectProjectId. MetaMask es la opción recomendada para esta versión.", "error");
    return;
  }

  try {
    const { default: EthereumProvider } = await import("https://esm.sh/@walletconnect/ethereum-provider@2");
    state.provider = await EthereumProvider.init({
      projectId: CONFIG.walletConnectProjectId,
      chains: [CONFIG.chainId],
      showQrModal: true,
      rpcMap: { [CONFIG.chainId]: CONFIG.rpcUrl },
    });
    const accounts = await state.provider.enable();
    state.account = accounts[0];
    setStatus(`Wallet conectada: ${shortAddress(state.account)}`, "ok");
    await loadOnChainState();
  } catch (error) {
    setStatus(error.message || "No se pudo conectar WalletConnect.", "error");
  }
}

async function ensureNetwork() {
  const chainId = await state.provider.request({ method: "eth_chainId" });
  if (chainId === CONFIG.chainHex) return;

  try {
    await state.provider.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: CONFIG.chainHex }],
    });
  } catch (error) {
    if (error.code !== 4902) throw error;
    await state.provider.request({
      method: "wallet_addEthereumChain",
      params: [{
        chainId: CONFIG.chainHex,
        chainName: CONFIG.chainName,
        rpcUrls: [CONFIG.rpcUrl],
        nativeCurrency: CONFIG.nativeCurrency,
        blockExplorerUrls: [CONFIG.blockExplorerUrl],
      }],
    });
  }
}

async function loadOnChainState() {
  if (!isConfigured(CONFIG.presaleAddress)) {
    setStatus("Falta configurar la dirección del contrato de preventa (presale).", "error");
    refreshUi();
    return;
  }

  state.phase = await readContract(CONFIG.presaleAddress, PRESALE_ABI, "currentPhase", []);
  state.priceUsd6 = await readContract(CONFIG.presaleAddress, PRESALE_ABI, "phases", [state.phase, 1n]);
  state.phaseEndTimes = await Promise.all(
    [0n, 1n, 2n].map((phase) => readContract(CONFIG.presaleAddress, PRESALE_ABI, "phases", [phase, 2n])),
  );
  state.totalSold = await readContract(CONFIG.presaleAddress, PRESALE_ABI, "totalSold", []);
  state.maxSellingAmount = await readContract(CONFIG.presaleAddress, PRESALE_ABI, "maxSellingAmount", []);
  state.startingTime = await readContract(CONFIG.presaleAddress, PRESALE_ABI, "startingTime", []);
  state.endingTime = await readContract(CONFIG.presaleAddress, PRESALE_ABI, "endingTime", []);
  state.reserved = state.account
    ? await readContract(CONFIG.presaleAddress, PRESALE_ABI, "userTokenBalance", [state.account])
    : 0n;
  try {
    state.ethPriceUsd18 = await readContract(CONFIG.presaleAddress, PRESALE_ABI, "getEtherPrice", []);
  } catch {
    state.ethPriceUsd18 = 0n;
  }

  for (const symbol of ["USDT", "USDC"]) {
    const address = tokenAddress(symbol);
    if (isConfigured(address)) {
      state.decimals[symbol] = Number(await readContract(address, ERC20_ABI, "decimals", []));
    }
  }

  refreshUi();
}

async function approveStable() {
  const symbol = elements.paymentToken.value;
  if (symbol === "ETH") {
    setStatus("ETH no necesita aprobación.", "ok");
    return;
  }

  await requireReady();
  const amount = parseAmount(elements.payAmount.value, state.decimals[symbol]);
  const address = tokenAddress(symbol);
  const tx = await writeContract(address, ERC20_ABI, "approve", [CONFIG.presaleAddress, amount]);
  setStatus(`Aprobación enviada: ${shortHash(tx)}`, "ok");
}

async function buyWkr() {
  await requireReady();
  const symbol = elements.paymentToken.value;
  let tx;

  if (symbol === "ETH") {
    if (!isSaleOpen()) {
      setStatus("La preventa todavia no esta activa o ya finalizo.", "error");
      return;
    }
    const value = parseAmount(elements.payAmount.value, 18);
    if (value < MIN_ETH_PURCHASE) {
      setStatus("La compra mínima con ETH es 0.0001 ETH.", "error");
      return;
    }
    if (state.ethPriceUsd18 && state.reserved + quoteEthWkr(value) > MAX_PRESALE_PER_WALLET) {
      setStatus("La compra supera el máximo de 10.000 WKR por dirección.", "error");
      return;
    }
    tx = await writeContract(CONFIG.presaleAddress, PRESALE_ABI, "buyWithEth", [], value);
  } else {
    if (!isSaleOpen()) {
      setStatus("La preventa todavia no esta activa o ya finalizo.", "error");
      return;
    }
    const amount = parseAmount(elements.payAmount.value, state.decimals[symbol]);
    if (amount < 10n ** BigInt(state.decimals[symbol])) {
      setStatus(`La compra mínima con ${symbol} es 1 ${symbol}.`, "error");
      return;
    }
    const address = tokenAddress(symbol);
    const allowance = await readContract(address, ERC20_ABI, "allowance", [state.account, CONFIG.presaleAddress]);
    if (allowance < amount) {
      setStatus(`Primero aprobá ${symbol} para esta compra.`, "error");
      return;
    }
    const quotedWkr = quoteStableWkr(amount, state.decimals[symbol]);
    if (state.reserved + quotedWkr > MAX_PRESALE_PER_WALLET) {
      setStatus("La compra supera el máximo de 10.000 WKR por dirección.", "error");
      return;
    }
    tx = await writeContract(CONFIG.presaleAddress, PRESALE_ABI, "buyWithStable", [address, amount]);
  }

  setStatus(`Compra enviada: ${shortHash(tx)}. Esperando confirmación...`, "ok");
  await waitForTransaction(tx);
  await loadOnChainState();
  setStatus(`Compra confirmada: ${shortHash(tx)}`, "ok");
}

async function claimWkr() {
  await requireReady();
  if (!isClaimOpen()) {
    setStatus("El reclamo todavia no esta abierto.", "error");
    return;
  }
  if (state.reserved === 0n) {
    setStatus("No tenés WKR reservados para reclamar.", "error");
    return;
  }

  const tx = await writeContract(CONFIG.presaleAddress, PRESALE_ABI, "claim", []);
  setStatus(`Reclamo enviado: ${shortHash(tx)}. Esperando confirmación...`, "ok");
  await waitForTransaction(tx);
  await loadOnChainState();
  setStatus(`Reclamo confirmado: ${shortHash(tx)}`, "ok");
}

async function requireReady() {
  if (!state.account) throw new Error("Conectá tu wallet primero.");
  if (!isConfigured(CONFIG.presaleAddress)) throw new Error("Configurá la dirección de preventa.");
}

function refreshUi() {
  elements.networkLabel.textContent = CONFIG.chainName;
  elements.phaseLabel.textContent = formatCurrentPhase();
  elements.priceLabel.textContent = state.priceUsd6 ? `${formatUsd6(state.priceUsd6)} USDT/USDC` : "-";
  const remaining = state.maxSellingAmount > state.totalSold ? state.maxSellingAmount - state.totalSold : 0n;
  elements.remainingLabel.textContent = state.maxSellingAmount ? `${formatToken(remaining, 18, 1)} WKR` : "-";
  elements.reservedLabel.textContent = state.account ? `${formatToken(state.reserved, 18, 1)} WKR` : "-";
  elements.timeLabel.textContent = formatSaleStatus();
  elements.approveButton.disabled = elements.paymentToken.value === "ETH";
  elements.claimStatusLabel.textContent = formatClaimStatus();
  elements.claimButton.disabled = !state.account || !isClaimOpen() || state.reserved === 0n;
  refreshQuote();
}

function handlePaymentTokenChange() {
  const symbol = elements.paymentToken.value;
  elements.payAmount.value = symbol === "ETH" ? "0.0001" : "1";
  setStatus(`Estás comprando con ${symbol}.`, "ok");
  refreshUi();
}

function isSaleOpen() {
  const now = BigInt(Math.floor(Date.now() / 1000));
  return state.startingTime > 0n && now > state.startingTime && now <= state.endingTime;
}

function formatCurrentPhase() {
  if (!state.priceUsd6) return "-";

  const phaseIndex = Number(state.phase);
  const phaseEnd = state.phaseEndTimes[phaseIndex];
  const phaseStart = phaseIndex === 0 ? state.startingTime : state.phaseEndTimes[phaseIndex - 1];
  const now = BigInt(Math.floor(Date.now() / 1000));
  if (!phaseEnd || !phaseStart || now > phaseEnd) return `Fase ${phaseIndex + 1}`;

  const remaining = phaseEnd > now ? phaseEnd - now : 0n;
  const totalDays = (phaseEnd - phaseStart) / 86_400n;
  return `Fase ${phaseIndex + 1} · faltan ${formatRemainingDays(remaining)} de ${totalDays} d`;
}

function formatRemainingDays(seconds) {
  const days = seconds / 86_400n;
  const hours = (seconds % 86_400n) / 3_600n;
  if (days > 0n) return `${days} d`;
  if (hours > 0n) return `${hours} h`;
  return `${(seconds % 3_600n) / 60n} min`;
}

function formatSaleStatus() {
  if (!state.startingTime || !state.endingTime) return "-";
  const now = BigInt(Math.floor(Date.now() / 1000));
  if (now <= state.startingTime) return `Inicia ${formatDate(state.startingTime)}`;
  if (now > state.endingTime) return "Finalizada";
  return `Activa hasta ${formatDate(state.endingTime)}`;
}

function isClaimOpen() {
  const now = BigInt(Math.floor(Date.now() / 1000));
  return state.endingTime > 0n && now > state.endingTime;
}

function formatClaimStatus() {
  if (!state.endingTime) return "Disponible al finalizar la preventa";
  if (isClaimOpen()) {
    return state.reserved > 0n ? "Reclamo abierto" : "Sin WKR reservados";
  }
  return `Disponible en ${formatDuration(state.endingTime - BigInt(Math.floor(Date.now() / 1000)))}`;
}

function refreshQuote() {
  const amount = elements.payAmount.value.trim();
  if (!amount || !state.priceUsd6) {
    elements.wkrQuote.textContent = "0 WKR";
    return;
  }

  try {
    const symbol = elements.paymentToken.value;
    const decimals = state.decimals[symbol];
    const parsed = parseAmount(amount, decimals);
    if (symbol === "ETH" && !state.ethPriceUsd18) {
      elements.wkrQuote.textContent = "Precio ETH no disponible";
      return;
    }
    const wkrAmount = symbol === "ETH" ? quoteEthWkr(parsed) : quoteStableWkr(parsed, decimals);
    elements.wkrQuote.textContent = `${formatToken(wkrAmount, 18, 1)} WKR`;
  } catch {
    elements.wkrQuote.textContent = "0 WKR";
  }
}

function quoteStableWkr(amount, decimals) {
  const usd18 = amount * 10n ** BigInt(18 - decimals);
  return (usd18 * 1_000_000n) / state.priceUsd6;
}

function quoteEthWkr(amount) {
  const usd18 = (amount * state.ethPriceUsd18) / 10n ** 18n;
  return (usd18 * 1_000_000n) / state.priceUsd6;
}

async function readContract(address, abi, name, args) {
  const data = encodeCall(abi, name, args);
  const result = await state.provider.request({
    method: "eth_call",
    params: [{ to: address, data }, "latest"],
  });
  return decodeUint(result);
}

async function writeContract(address, abi, name, args, value = 0n) {
  const data = encodeCall(abi, name, args);
  const tx = { from: state.account, to: address, data };
  if (value > 0n) tx.value = `0x${value.toString(16)}`;
  const gasPrice = BigInt(await state.provider.request({ method: "eth_gasPrice" }));
  tx.gasPrice = `0x${((gasPrice * 125n) / 100n).toString(16)}`;
  return state.provider.request({ method: "eth_sendTransaction", params: [tx] });
}

async function waitForTransaction(txHash) {
  for (let attempt = 0; attempt < 120; attempt++) {
    const receipt = await state.provider.request({
      method: "eth_getTransactionReceipt",
      params: [txHash],
    });
    if (receipt) {
      if (receipt.status === "0x0") throw new Error("La transacción fue revertida.");
      return receipt;
    }
    await new Promise((resolve) => setTimeout(resolve, 1_500));
  }
  throw new Error("La confirmación está tardando demasiado. Revisá la transacción en el explorador.");
}

function encodeCall(abi, name, args) {
  const item = abi.find((entry) => entry.name === name);
  const signature = `${item.name}(${item.inputs.map((input) => input.type).join(",")})`;
  const selector = keccakSelector(signature);
  const encodedArgs = args.map((arg, index) => encodeArg(item.inputs[index].type, arg)).join("");
  return selector + encodedArgs;
}

function encodeArg(type, value) {
  if (type === "address") return cleanHex(value).padStart(64, "0");
  if (type.startsWith("uint")) return BigInt(value).toString(16).padStart(64, "0");
  throw new Error(`Unsupported ABI type: ${type}`);
}

function decodeUint(hex) {
  return BigInt(hex || "0x0");
}

function parseAmount(value, decimals) {
  const normalized = value.replace(",", ".").trim();
  if (!/^\d+(\.\d+)?$/.test(normalized)) throw new Error("Monto inválido.");
  const [whole, fraction = ""] = normalized.split(".");
  const padded = fraction.padEnd(decimals, "0").slice(0, decimals);
  return BigInt(whole) * 10n ** BigInt(decimals) + BigInt(padded || "0");
}

function formatToken(value, decimals, precision = 4) {
  const base = 10n ** BigInt(decimals);
  const whole = value / base;
  const fraction = value % base;
  const fractionText = fraction.toString().padStart(decimals, "0").slice(0, precision);
  return fractionText && BigInt(fractionText) > 0n ? `${whole}.${fractionText}` : whole.toString();
}

function formatUsd6(value) {
  return `$${formatToken(value, 6, 4)}`;
}

function tokenAddress(symbol) {
  if (symbol === "USDT") return CONFIG.usdtAddress;
  if (symbol === "USDC") return CONFIG.usdcAddress;
  return CONFIG.wkrAddress;
}

function setStatus(message, type = "") {
  elements.statusMessage.textContent = message;
  elements.statusMessage.className = `status-message ${type}`.trim();
}

async function runAction(action) {
  try {
    await action();
  } catch (error) {
    setStatus(formatWalletError(error), "error");
  }
}

function formatWalletError(error) {
  if (error && error.code === 4001) return "Transacción rechazada en la wallet.";
  const message = (error && (error.shortMessage || error.reason || error.message)) || "No se pudo completar la operación.";
  if (message.includes("Price too old")) return "El precio ETH del oráculo está vencido. Debe actualizarse antes de comprar.";
  if (message.includes("insufficient funds")) return "Saldo ETH insuficiente para la compra y el gas.";
  if (message.includes("max fee per gas less than block base fee")) {
    return "La comisión de red cambió antes del envío. Intentá nuevamente; la app actualizará el gas automáticamente.";
  }
  if (message.includes("Exceeds max presale per wallet")) return "La compra supera el máximo de 10.000 WKR por dirección.";
  return message;
}

function isConfigured(address) {
  return /^0x[0-9a-fA-F]{40}$/.test(address) && !/^0x0{40}$/i.test(address);
}

function cleanHex(value) {
  return String(value).replace(/^0x/i, "");
}

function shortAddress(address) {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function shortHash(hash) {
  return `${hash.slice(0, 10)}...${hash.slice(-6)}`;
}

function keccakSelector(signature) {
  const known = {
    "approve(address,uint256)": "0x095ea7b3",
    "allowance(address,address)": "0xdd62ed3e",
    "balanceOf(address)": "0x70a08231",
    "decimals()": "0x313ce567",
    "buyWithStable(address,uint256)": "0xec11125e",
    "buyWithEth()": "0x11b5444f",
    "claim()": "0x4e71d92d",
    "getEtherPrice()": "0xca7c4dba",
    "currentPhase()": "0x055ad42e",
    "phases(uint256,uint256)": "0x918dafa4",
    "totalSold()": "0x9106d7ba",
    "maxSellingAmount()": "0x6f278623",
    "userTokenBalance(address)": "0x29a87023",
    "startingTime()": "0x39518b5e",
    "endingTime()": "0x6c47a6c3",
    "paused()": "0x5c975abb",
  };
  if (!known[signature]) throw new Error(`Missing selector: ${signature}`);
  return known[signature];
}

function formatDate(timestamp) {
  return new Date(Number(timestamp) * 1000).toLocaleString("es-AR", {
    dateStyle: "short",
    timeStyle: "short",
  });
}

function formatDuration(seconds) {
  if (seconds <= 0n) return "0 min";
  const days = seconds / 86_400n;
  const hours = (seconds % 86_400n) / 3_600n;
  const minutes = (seconds % 3_600n) / 60n;
  const parts = [];
  if (days > 0n) parts.push(`${days} d`);
  if (hours > 0n || days > 0n) parts.push(`${hours} h`);
  parts.push(`${minutes} min`);
  return parts.join(" ");
}
