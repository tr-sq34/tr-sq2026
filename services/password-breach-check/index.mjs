export const handler = async (event) => {
  const { prefix, suffix } = event ?? {};
  if (!/^[A-F0-9]{5}$/.test(prefix ?? '') || !/^[A-F0-9]{35}$/.test(suffix ?? '')) {
    throw new Error('invalid password hash range request');
  }
  const response = await fetch(`https://api.pwnedpasswords.com/range/${prefix}`, {
    headers: { 'Add-Padding': 'true', 'User-Agent': 'TurkSquarePasswordSafety/1.0' },
    signal: AbortSignal.timeout(3000),
  });
  if (!response.ok) throw new Error('breach range lookup unavailable');
  const breached = (await response.text()).split(/\r?\n/).some((line) => line.split(':', 1)[0] === suffix);
  return { breached };
};
