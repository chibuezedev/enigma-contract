import express from "express";
import cors from "cors";
import { RpcProvider, Contract, Account, cairo, num } from "starknet";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
require("dotenv").config();

const app = express();
app.use(cors());
app.use(express.json());

const provider = new RpcProvider({ nodeUrl: process.env.RPC_URL });

const getAccount = () =>
  new Account(provider, process.env.ACCOUNT_ADDRESS, process.env.PRIVATE_KEY);

let vaultContract = null;

async function getVault() {
  if (vaultContract) return vaultContract;
  const { abi } = await provider.getClassAt(process.env.VAULT_ADDRESS);
  vaultContract = new Contract(abi, process.env.VAULT_ADDRESS, provider);
  return vaultContract;
}

app.get("/price", async (req, res) => {
  try {
    const vault = await getVault();
    const price = await vault.get_btc_price();
    res.json({ price: num.toHex(price) });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/price", async (req, res) => {
  try {
    const account = getAccount();
    const vault = await getVault();
    const connected = new Contract(vault.abi, vault.address, account);
    const tx = await connected.set_btc_price(cairo.uint256(req.body.price));
    await provider.waitForTransaction(tx.transaction_hash);
    res.json({ tx: tx.transaction_hash });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get("/position/:address", async (req, res) => {
  try {
    const vault = await getVault();
    const result = await vault.get_position(req.params.address);
    const healthFactor = await vault.get_health_factor(req.params.address);
    res.json({
      collateral: num.toHex(result[0]),
      debt: num.toHex(result[1]),
      healthFactor: num.toHex(healthFactor),
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/deposit", async (req, res) => {
  try {
    const account = getAccount();
    const vault = await getVault();
    const connected = new Contract(vault.abi, vault.address, account);
    const tx = await connected.deposit_collateral(cairo.uint256(req.body.amount));
    await provider.waitForTransaction(tx.transaction_hash);
    res.json({ tx: tx.transaction_hash });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/borrow", async (req, res) => {
  try {
    const account = getAccount();
    const vault = await getVault();
    const connected = new Contract(vault.abi, vault.address, account);
    const tx = await connected.borrow(cairo.uint256(req.body.amount));
    await provider.waitForTransaction(tx.transaction_hash);
    res.json({ tx: tx.transaction_hash });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/repay", async (req, res) => {
  try {
    const account = getAccount();
    const vault = await getVault();
    const connected = new Contract(vault.abi, vault.address, account);
    const tx = await connected.repay(cairo.uint256(req.body.amount));
    await provider.waitForTransaction(tx.transaction_hash);
    res.json({ tx: tx.transaction_hash });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/withdraw", async (req, res) => {
  try {
    const account = getAccount();
    const vault = await getVault();
    const connected = new Contract(vault.abi, vault.address, account);
    const tx = await connected.withdraw_collateral(cairo.uint256(req.body.amount));
    await provider.waitForTransaction(tx.transaction_hash);
    res.json({ tx: tx.transaction_hash });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/liquidate", async (req, res) => {
  try {
    const account = getAccount();
    const vault = await getVault();
    const connected = new Contract(vault.abi, vault.address, account);
    const tx = await connected.liquidate(req.body.user);
    await provider.waitForTransaction(tx.transaction_hash);
    res.json({ tx: tx.transaction_hash });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/mint/collateral", async (req, res) => {
  try {
    const account = getAccount();
    const amount = BigInt(req.body.amount);
    const low = (amount & BigInt("0xffffffffffffffffffffffffffffffff")).toString();
    const high = (amount >> BigInt(128)).toString();
    const tx = await account.execute({
      contractAddress: process.env.COLLATERAL_TOKEN_ADDRESS,
      entrypoint: "mint",
      calldata: [req.body.to, low, high],
    });
    await provider.waitForTransaction(tx.transaction_hash);
    res.json({ tx: tx.transaction_hash });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/mint/debt", async (req, res) => {
  try {
    const account = getAccount();
    const amount = BigInt(req.body.amount);
    const low = (amount & BigInt("0xffffffffffffffffffffffffffffffff")).toString();
    const high = (amount >> BigInt(128)).toString();
    const tx = await account.execute({
      contractAddress: process.env.DEBT_TOKEN_ADDRESS,
      entrypoint: "mint",
      calldata: [req.body.to, low, high],
    });
    await provider.waitForTransaction(tx.transaction_hash);
    res.json({ tx: tx.transaction_hash });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/approve/collateral", async (req, res) => {
  try {
    const account = getAccount();
    const amount = BigInt(req.body.amount);
    const low = (amount & BigInt("0xffffffffffffffffffffffffffffffff")).toString();
    const high = (amount >> BigInt(128)).toString();
    const tx = await account.execute({
      contractAddress: process.env.COLLATERAL_TOKEN_ADDRESS,
      entrypoint: "approve",
      calldata: [process.env.VAULT_ADDRESS, low, high],
    });
    await provider.waitForTransaction(tx.transaction_hash);
    res.json({ tx: tx.transaction_hash });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post("/approve/debt", async (req, res) => {
  try {
    const account = getAccount();
    const amount = BigInt(req.body.amount);
    const low = (amount & BigInt("0xffffffffffffffffffffffffffffffff")).toString();
    const high = (amount >> BigInt(128)).toString();
    const tx = await account.execute({
      contractAddress: process.env.DEBT_TOKEN_ADDRESS,
      entrypoint: "approve",
      calldata: [process.env.VAULT_ADDRESS, low, high],
    });
    await provider.waitForTransaction(tx.transaction_hash);
    res.json({ tx: tx.transaction_hash });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log(`CDP backend running on :${PORT}`));