import { BlobServiceClient, StorageSharedKeyCredential, generateBlobSASQueryParameters, BlobSASPermissions, SASProtocol } from "@azure/storage-blob";

const accountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;
const accountKey = process.env.AZURE_STORAGE_ACCOUNT_KEY;
const containerName = process.env.AZURE_VERIFICATION_CONTAINER_NAME ?? "verification";

let blobServiceClient: BlobServiceClient | undefined;

function getClient(): BlobServiceClient {
  if (!accountName || !accountKey) {
    throw new Error("AZURE_STORAGE_ACCOUNT_NAME and AZURE_STORAGE_ACCOUNT_KEY are required");
  }
  if (!blobServiceClient) {
    const credential = new StorageSharedKeyCredential(accountName, accountKey);
    blobServiceClient = new BlobServiceClient(
      `https://${accountName}.blob.core.windows.net`,
      credential
    );
  }
  return blobServiceClient;
}

export function getContainerClient() {
  return getClient().getContainerClient(containerName);
}

export async function generateUploadSasUrl(
  blobName: string,
  contentType: string,
  contentLength: number,
  checksumSha256Base64: string,
  expiresInSeconds = 300
): Promise<string> {
  if (!accountName || !accountKey) {
    throw new Error("Azure Storage credentials are not configured");
  }
  const startsOn = new Date();
  const expiresOn = new Date(startsOn.getTime() + expiresInSeconds * 1000);
  const credential = new StorageSharedKeyCredential(accountName, accountKey);
  const sas = generateBlobSASQueryParameters(
    {
      containerName,
      blobName,
      permissions: BlobSASPermissions.parse("cw"),
      startsOn,
      expiresOn,
      protocol: SASProtocol.Https,
      contentType,
      contentLength,
      contentHash: checksumSha256Base64,
    },
    credential
  );
  return `https://${accountName}.blob.core.windows.net/${containerName}/${blobName}?${sas}`;
}

export async function headBlob(blobName: string) {
  const container = getContainerClient();
  const blob = container.getBlobClient(blobName);
  const props = await blob.getProperties();
  return {
    contentLength: props.contentLength,
    contentType: props.contentType,
    checksumSha256: props.contentHash,
  };
}
