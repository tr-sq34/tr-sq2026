const { app } = require('@azure/functions');

app.http('passwordBreachCheck', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'passwordBreachCheck',
  handler: async (request, context) => {
    const body = await request.json();
    const { prefix, suffix } = body ?? {};
    if (!/^[A-F0-9]{5}$/.test(prefix ?? '') || !/^[A-F0-9]{35}$/.test(suffix ?? '')) {
      return { status: 400, jsonBody: { error: 'invalid password hash range request' } };
    }

    const url = `https://api.pwnedpasswords.com/range/${prefix}`;
    let lastError;

    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        const response = await fetch(url, {
          headers: {
            'Add-Padding': 'true',
            'User-Agent': 'TurkSquarePasswordSafety/1.0',
          },
          signal: AbortSignal.timeout(4000),
        });
        if (!response.ok) throw new Error(`breach range lookup returned ${response.status}`);
        const breached = (await response.text())
          .split(/\r?\n/)
          .some((line) => line.split(':', 1)[0] === suffix);
        return { jsonBody: { breached } };
      } catch (error) {
        lastError = error;
        if (attempt === 0) await new Promise((resolve) => setTimeout(resolve, 200));
      }
    }

    context.error('breach range lookup unavailable', lastError);
    return { status: 503, jsonBody: { error: 'breach range lookup unavailable' } };
  },
});