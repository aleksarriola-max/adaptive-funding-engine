interface Props {
  status: string;
  digest?: string;
}

export default function StatusBanner({ status, digest }: Props) {
  if (!status) return null;
  const isError = status.startsWith('Error') || status.startsWith('Transaction failed');
  return (
    <div className={`p-3 rounded-lg text-sm border flex items-start justify-between gap-4 ${
      isError
        ? 'bg-red-900/30 text-red-300 border-red-700'
        : 'bg-emerald-900/30 text-emerald-300 border-emerald-700'
    }`}>
      <span>{status}</span>
      {digest && !isError && (
        <a
          href={`https://suiscan.xyz/testnet/tx/${digest}`}
          target="_blank"
          rel="noreferrer"
          className="shrink-0 font-mono text-xs underline opacity-70 hover:opacity-100"
        >
          {digest.slice(0, 8)}…{digest.slice(-6)} ↗
        </a>
      )}
    </div>
  );
}
