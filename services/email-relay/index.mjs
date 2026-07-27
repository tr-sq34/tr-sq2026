import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';

const secrets = new SecretsManagerClient({});
let apiKey;

async function resendKey() {
  if (apiKey) return apiKey;
  const value = await secrets.send(new GetSecretValueCommand({ SecretId: process.env.RESEND_API_KEY_SECRET_ARN }));
  apiKey = value.SecretString;
  if (!apiKey?.startsWith('re_')) throw new Error('Invalid Resend API key secret');
  return apiKey;
}

export const handler = async (event) => {
  const key = await resendKey();
  for (const record of event.Records ?? []) {
    const message = JSON.parse(record.body);
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: message.from,
        to: [message.recipient],
        subject: message.subject,
        text: message.text,
        tags: [{ name: 'category', value: message.category }],
      }),
    });
    if (!response.ok) throw new Error(`Resend delivery failed with HTTP ${response.status}`);
  }
};
