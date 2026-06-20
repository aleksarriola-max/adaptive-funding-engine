import { useState, useEffect } from 'react';

export function useStatus(duration = 6000) {
  const [status,   setStatus]   = useState('');
  const [digest,   setDigest]   = useState('');

  useEffect(() => {
    if (!status) return;
    const t = setTimeout(() => { setStatus(''); setDigest(''); }, duration);
    return () => clearTimeout(t);
  }, [status, duration]);

  function ok(msg: string, txDigest?: string) {
    setStatus(msg);
    if (txDigest) setDigest(txDigest);
  }

  function err(e: Error) {
    // Surface Move abort codes in a readable way
    const match = e.message.match(/MoveAbort[^,]*,\s*(\d+)/);
    setStatus(match ? `Transaction failed (abort code ${match[1]})` : 'Error: ' + e.message);
    setDigest('');
  }

  return { status, digest, ok, err };
}
