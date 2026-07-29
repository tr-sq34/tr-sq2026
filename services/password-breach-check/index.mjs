export const handler = async (event) => {
  const { prefix, suffix } = event ?? {};
  if (!/^[A-F0-9]{5}$/.test(prefix ?? '') || !/^[A-F0-9]{35}$/.test(suffix ?? '')) {
    throw new Error('invalid password hash range request');
  }
  const url = `https://api.pwnedpasswords.com/range/${prefix}`;
  let lastError;

  // The HIBP range API receives only the first five SHA-1 characters. A
  // single retry shields account creation from transient provider/network
  // failures without ever accepting an unchecked password.
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
      return { breached };
    } catch (error) {
      lastError = error;
      if (attempt === 0) await new Promise((resolve) => setTimeout(resolve, 200));
    }
  }

  throw new Error('breach range lookup unavailable', { cause: lastError });
};
