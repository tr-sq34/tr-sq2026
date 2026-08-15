import { BlobServiceClient, StorageSharedKeyCredential, generateBlobSASQueryParameters, BlobSASPermissions, SASProtocol } from "@azure/storage-blob";

const accountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;
const accountKey = process.env.AZURE_STORAGE_ACCOUNT_KEY;
const containerName = process.env.AZURE_MEDIA_CONTAINER_NAME ?? "community-media";

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

/**
 * Karantinaya yazma bağlantısı.
 *
 * Bu imza eskiden bir uzunluk ve bir SHA-256 daha alıyordu, ikisini de
 * kullanmadan. Bir Blob SAS'ı yalnızca konteyneri, blob adını, izinleri ve
 * süreyi imzalayabilir; gövdenin boyutunu ya da özetini imzaya bağlamanın bir
 * yolu yok. Parametreleri alıp yok saymak, çağıran tarafa var olmayan bir
 * güvence veriyordu. İkisi de artık gerçekten uygulanabildikleri yerde
 * uygulanıyor: boyut ve içerik türü /media/uploads/complete içinde blobun kendi
 * özelliklerinden, SHA-256 ise baytları eline alan tek yerde - medya
 * işleyicide.
 *
 * İçerik türü de imzaya girmiyordu: SAS'taki `contentType` alanı okuma
 * yanıtının başlığını değiştiren `rsct` değerine karşılık geliyor, yazma
 * isteğiyle ilgisi yok. Bu bağlantının okuma izni de zaten yok.
 */
export async function generateMediaUploadSasUrl(
  blobName: string,
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
    },
    credential
  );
  return `https://${accountName}.blob.core.windows.net/${containerName}/${blobName}?${sas}`;
}

export async function generateMediaReadSasUrl(blobName: string, expiresInSeconds = 300): Promise<string> {
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
      permissions: BlobSASPermissions.parse("r"),
      startsOn,
      expiresOn,
      protocol: SASProtocol.Https,
    },
    credential
  );
  return `https://${accountName}.blob.core.windows.net/${containerName}/${blobName}?${sas}`;
}

/**
 * Karantinadaki nesnenin beyan edilenle aynı olup olmadığına bakılan iki alan.
 *
 * Burada eskiden bir `checksumSha256` alanı vardı ve içine Azure'un
 * `contentHash` değeri konuyordu. O değer bir MD5, üstelik yalnızca istemci
 * Content-MD5 gönderdiyse dolu. Çağıran taraf onu beklenen SHA-256 ile
 * karşılaştırdığı için karşılaştırma hiçbir koşulda tutmuyordu: her yükleme,
 * dosya sapasağlam yerine ulaşmış olsa bile "doğrulanamadı" diye geri
 * dönüyordu. Yanlış adlandırılmış bir alanı taşımaktansa kaldırmak doğru;
 * SHA-256 baytların indirildiği tek yerde, medya işleyicide doğrulanıyor.
 */
export async function headMediaBlob(blobName: string) {
  const container = getContainerClient();
  const blob = container.getBlobClient(blobName);
  const props = await blob.getProperties();
  return {
    contentLength: props.contentLength,
    contentType: props.contentType,
  };
}

export async function downloadMediaBlob(blobName: string): Promise<Buffer> {
  const container = getContainerClient();
  const blob = container.getBlockBlobClient(blobName);
  const response = await blob.download(0);
  if (!response.readableStreamBody) {
    throw new Error(`Blob ${blobName} has no readable body`);
  }
  const chunks: Buffer[] = [];
  for await (const chunk of response.readableStreamBody as unknown as AsyncIterable<Buffer>) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export async function uploadMediaBlob(blobName: string, body: Buffer, contentType: string): Promise<void> {
  const container = getContainerClient();
  const blob = container.getBlockBlobClient(blobName);
  await blob.upload(body, body.length, { blobHTTPHeaders: { blobContentType: contentType } });
}

export async function deleteMediaBlob(blobName: string): Promise<void> {
  const container = getContainerClient();
  const blob = container.getBlobClient(blobName);
  await blob.deleteIfExists();
}
