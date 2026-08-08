import { ManagedIdentityCredential } from "@azure/identity";
import { KeyClient } from "@azure/keyvault-keys";

const keyVaultUrl = process.env.AZURE_KEY_VAULT_URL;
const managedIdentityClientId = process.env.AZURE_CLIENT_ID;

if (!keyVaultUrl) {
  throw new Error("AZURE_KEY_VAULT_URL is required");
}
if (!managedIdentityClientId) {
  throw new Error("AZURE_CLIENT_ID is required for Key Vault managed identity access");
}

const credential = new ManagedIdentityCredential(managedIdentityClientId);

export const keyClient = new KeyClient(keyVaultUrl, credential);

export async function getIdentityVerificationKey(): Promise<{
  kty: "RSA";
  n: string;
  e: string;
  alg: "RS256";
}> {
  const keyName = process.env.AZURE_JWT_SIGNING_KEY_NAME ?? "turksquare-identity-jwt-signing";
  const key = await keyClient.getKey(keyName);
  if (!key) {
    throw new Error(`Identity signing key ${keyName} not found in Key Vault`);
  }
  if (!key.key?.n || !key.key?.e) {
    throw new Error("Identity signing key does not contain RSA public components");
  }
  return {
    kty: key.keyType === "RSA" ? "RSA" : "RSA",
    n: Buffer.from(key.key.n).toString("base64url"),
    e: Buffer.from(key.key.e).toString("base64url"),
    alg: "RS256",
  };
}
