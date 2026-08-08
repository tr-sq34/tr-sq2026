const { app } = require('@azure/functions');

app.http('emailRelay', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'emailRelay',
  handler: async (request, context) => {
    const apiKey = process.env.RESEND_API_KEY;
    if (!apiKey?.startsWith('re_')) {
      context.error('Invalid or missing Resend API key');
      return { status: 500, jsonBody: { error: 'email relay is not configured' } };
    }

    const message = await request.json();
    if (!message || typeof message !== 'object') {
      return { status: 400, jsonBody: { error: 'invalid request body' } };
    }

    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        'Idempotency-Key': message.idempotencyKey,
      },
      body: JSON.stringify({
        from: message.from,
        to: [message.recipient],
        subject: message.subject,
        text: message.text,
        tags: [{ name: 'category', value: message.category }],
      }),
    });

    if (!response.ok) {
      const body = await response.text();
      context.error({ status: response.status, body }, 'Resend delivery failed');
      return { status: 502, jsonBody: { error: 'email delivery failed' } };
    }

    const result = await response.json();
    context.log(JSON.stringify({ event: 'transactional_email_accepted', category: message.category, status: response.status, id: result.id }));
    return { jsonBody: { data: result } };
  },
});