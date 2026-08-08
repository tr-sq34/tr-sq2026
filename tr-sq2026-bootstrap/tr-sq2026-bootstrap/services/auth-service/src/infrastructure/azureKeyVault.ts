import { ManagedIdentityCredential } from "@azure/identity";
import { KeyClient, CryptographyClient } from "@azure/keyvault-keys";
import { SecretClient } from "@azure/keyvault-secrets";

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
export const secretClient = new SecretClient(keyVaultUrl, credential);

export async function getSigningKeyClient(keyName: string): Promise<CryptographyClient> {
  const key = await keyClient.getKey(keyName);
  if (!key) {
    throw new Error(`Key ${keyName} not found in Key Vault`);
  }
  return new CryptographyClient(key, credential);
}

export async function signWithKeyVault(
  keyName: string,
  data: Buffer
): Promise<Buffer> {
  const cryptoClient = await getSigningKeyClient(keyName);
  const result = await cryptoClient.signData("RS256", data);
  if (!result || !result.result) {
    throw new Error("Key Vault sign operation returned no result");
  }
  return Buffer.from(result.result);
}

export async function verifyWithKeyVault(
  keyName: string,
  data: Buffer,
  signature: Buffer
): Promise<boolean> {
  const cryptoClient = await getSigningKeyClient(keyName);
  const result = await cryptoClient.verifyData("RS256", data, signature);
  return result.result;
}

export async function getSecret(name: string): Promise<string | undefined> {
  try {
    const secret = await secretClient.getSecret(name);
    return secret.value;
  } catch (err: any) {
    if (err.statusCode === 404) return undefined;
    throw err;
  }
}

export async function getSecretOrThrow(name: string): Promise<string> {
  const value = await getSecret(name);
  if (!value) {
    throw new Error(`Secret ${name} not found in Key Vault`);
  }
  return value;
}
