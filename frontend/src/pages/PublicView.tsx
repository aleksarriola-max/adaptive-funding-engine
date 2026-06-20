import { useState } from 'react';
import { usePool } from '../hooks/usePool';
import { useAgreements } from '../hooks/useAgreements';

function fmt(mist: bigint) { return (Number(mist) / 1e9).toFixed(4) + ' SUI'; }

const STATE_INFO: Record<number, [string, string]> = {
  0: ['Locked',    'bg-slate-600 text-slate-300'],
  1: ['Open',      'bg-amber-900 text-amber-300'],
  2: ['Submitted', 'bg-purple-900 text-purple-300'],
  3: ['Streaming', 'bg-blue-900 text-blue-300'],
  4: ['Paid',      'bg-emerald-900 text-emerald-300'],
  5: ['Partial',   'bg-teal-900 text-teal-300'],
  6: ['Rejected',  'bg-red-900 text-red-300'],
  7: ['Expired',   'bg-slate-700 text-slate-400'],
  8: ['Recycled',  'bg-slate-700 text-slate-400'],
};

function CopyAddress({ address }: { address: string }) {
  const [copied, setCopied] = useState(false);
  function copy() {
    navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }
  return (
    <button onClick={copy} className="font-mono text-slate-300 hover:text-indigo-300 transition-colors text-xs">
      {address.slice(0, 10)}…{address.slice(-6)} {copied ? '✓' : '⧉'}
    </button>
  );
}

export default function PublicView() {
  const { pool, isLoading: poolLoading, refetch: refetchPool } = usePool();
  const { data: agreements = [], isLoading: agLoading, refetch: refetchAg } = useAgreements();

  const totalDisbursed = agreements.reduce((s, a) => s + a.releasedTotal, 0n);
  const activeCount    = agreements.filter(a => a.active).length;

  function refresh() { refetchPool(); refetchAg(); }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-bold">Public View</h2>
        <button onClick={refresh}
          className="text-xs text-slate-400 hover:text-slate-200 border border-slate-700 rounded px-3 py-1.5 transition-colors">
          ↻ Refresh
        </button>
      </div>

      {(poolLoading || agLoading) && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {Array(4).fill(0).map((_, i) => (
            <div key={i} className="bg-slate-800 rounded-lg p-4 border border-slate-700 animate-pulse h-20" />
          ))}
        </div>
      )}

      {pool && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {[
            { label: 'Pool Balance',      value: fmt(pool.balance) },
            { label: 'APY',               value: (pool.apyBps / 100).toFixed(2) + '%' },
            { label: 'Active Agreements', value: String(activeCount) },
            { label: 'Total Disbursed',   value: fmt(totalDisbursed) },
          ].map(({ label, value }) => (
            <div key={label} className="bg-slate-800 rounded-lg p-4 border border-slate-700">
              <p className="text-xs text-slate-400 mb-1">{label}</p>
              <p className="text-lg font-semibold text-indigo-300">{value}</p>
            </div>
          ))}
        </div>
      )}

      {/* Protocol description */}
      <div className="bg-slate-800/50 rounded-lg p-4 border border-slate-700 text-sm text-slate-400 space-y-1">
        <p className="text-slate-300 font-medium">How it works</p>
        <p>Managers create milestone-based funding agreements. Recipients submit proof of work. Reviewers vote — quorum triggers adaptive payout with late-decay penalties and on-time bonuses. Funds vest linearly, stepped, or on an accelerating curve. Withheld funds recycle back to the pool for the next recipient in the waitlist.</p>
      </div>

      <div className="space-y-3">
        <h3 className="font-semibold text-lg">All On-Chain Agreements</h3>

        {!agLoading && agreements.length === 0 && (
          <div className="bg-slate-800 rounded-lg p-8 border border-slate-700 text-center">
            <p className="text-slate-400">No agreements found on-chain.</p>
          </div>
        )}

        {agreements.map(a => (
          <div key={a.id} className="bg-slate-800 rounded-lg p-4 border border-slate-700">
            <div className="flex items-start justify-between mb-3 gap-4">
              <div className="min-w-0">
                <p className="text-xs font-mono text-slate-500 truncate">{a.id}</p>
                <div className="flex items-center gap-2 mt-1">
                  <span className="text-xs text-slate-400">Recipient:</span>
                  <CopyAddress address={a.recipient} />
                </div>
                <p className="text-xs text-slate-500 mt-0.5">
                  Quorum: {String(a.quorumThreshold)} · Reviewers: {a.reviewers.length}
                </p>
              </div>
              <div className="text-right shrink-0">
                <p className="text-indigo-300 font-semibold">{fmt(a.totalAmount)}</p>
                <p className="text-xs text-emerald-400">{fmt(a.releasedTotal)} released</p>
                <span className={`inline-block mt-1 text-xs px-2 py-0.5 rounded-full ${a.active ? 'bg-emerald-900 text-emerald-300' : 'bg-indigo-900 text-indigo-300'}`}>
                  {a.active ? 'Active' : '✓ Done'}
                </span>
              </div>
            </div>

            <div className="flex gap-2 flex-wrap">
              {a.milestones.map((m, idx) => {
                const [label, cls] = STATE_INFO[m.state] ?? ['Unknown', 'bg-slate-700 text-slate-400'];
                return (
                  <span key={idx} className={`text-xs px-2 py-0.5 rounded-full ${cls}`}>
                    M{idx + 1}: {label} · {fmt(m.amount)}
                  </span>
                );
              })}
            </div>

            {/* Explorer link */}
            <a href={`https://suiscan.xyz/testnet/object/${a.id}`} target="_blank" rel="noreferrer"
              className="inline-block mt-2 text-xs text-slate-500 hover:text-indigo-400 transition-colors">
              View on Suiscan ↗
            </a>
          </div>
        ))}
      </div>
    </div>
  );
}
