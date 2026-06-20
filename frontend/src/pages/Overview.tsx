import { usePool } from '../hooks/usePool';
import { useAgreements } from '../hooks/useAgreements';

function fmt(mist: bigint) { return (Number(mist) / 1e9).toFixed(4) + ' SUI'; }
function n(b: bigint) { return Number(b) / 1e9; }

function Kpi({ icon, label, value, color }: { icon: string; label: string; value: string; color?: string }) {
  return (
    <div className="bg-slate-800 border border-slate-700 rounded-xl p-4 flex items-center gap-3">
      <div
        className="w-10 h-10 rounded-xl bg-slate-700 flex items-center justify-center text-xl shrink-0"
        style={color ? { color } : { color: '#818cf8' }}
      >
        {icon}
      </div>
      <div>
        <p className="text-lg font-semibold text-slate-100" style={color ? { color } : undefined}>{value}</p>
        <p className="text-xs text-slate-400">{label}</p>
      </div>
    </div>
  );
}

interface Props { onTabChange: (tab: string) => void; }

export default function Overview({ onTabChange }: Props) {
  const { pool, isLoading: poolLoading } = usePool();
  const { data: agreements = [], isLoading: agLoading } = useAgreements();

  const escrowed  = agreements.filter(a => a.active).reduce((s, a) => s + a.totalAmount - a.releasedTotal, 0n);
  const released  = agreements.reduce((s, a) => s + a.releasedTotal, 0n);
  const recycled  = pool?.totalRecycled ?? 0n;
  const active    = agreements.filter(a => a.active).length;

  const flows   = [n(escrowed), n(released), n(recycled)];
  const maxFlow = Math.max(1, ...flows);
  const sw      = (val: bigint) => Math.max(3, 3 + (n(val) / maxFlow) * 22);

  const isLoading = poolLoading || agLoading;

  return (
    <div className="space-y-6">
      {/* Hero band */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 rounded-2xl border border-slate-700 p-6"
        style={{ background: 'linear-gradient(135deg, rgba(79,124,255,.14), rgba(20,184,166,.08))' }}>
        <div>
          <h2 className="text-2xl font-bold mb-1">Program at a glance</h2>
          <p className="text-slate-400 text-sm">Every coin in this program is governed on-chain. Watch it move.</p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <button onClick={() => onTabChange('manager')}
            className="bg-indigo-600 hover:bg-indigo-500 rounded-lg px-4 py-2 text-sm font-medium transition-colors">
            Create an agreement
          </button>
          <button onClick={() => onTabChange('public')}
            className="border border-slate-600 hover:border-slate-400 text-slate-300 hover:text-slate-100 rounded-lg px-4 py-2 text-sm transition-colors">
            Public transparency →
          </button>
        </div>
      </div>

      {/* Differentiators strip */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        {[
          { icon: '🔒', title: 'Proof-gated', body: 'Quorum-verified evidence unlocks every tranche — no rubber stamps.' },
          { icon: '♻', title: 'Self-recycling', body: 'Unused capital returns to the pool and automatically funds the next recipient.' },
          { icon: '〜', title: 'Streamed & adaptive', body: 'Performance-priced payouts that vest linearly, stepped, or accelerating.' },
        ].map(d => (
          <div key={d.title} className="bg-slate-800 border border-slate-700 rounded-xl p-4 flex gap-3 items-start">
            <span className="text-2xl">{d.icon}</span>
            <div>
              <p className="font-semibold text-slate-100 mb-0.5">{d.title}</p>
              <p className="text-xs text-slate-400">{d.body}</p>
            </div>
          </div>
        ))}
      </div>

      {/* Capital flow diagram */}
      <div className="bg-slate-800 border border-slate-700 rounded-xl p-4"
        style={{ background: 'radial-gradient(700px 300px at 20% -20%, rgba(79,124,255,.10), transparent), #1e293b' }}>
        {isLoading ? (
          <div className="h-52 rounded-xl" style={{ background: 'linear-gradient(90deg, #1e293b 25%, #334155 50%, #1e293b 75%)', backgroundSize: '200% 100%', animation: 'sk 1.2s ease infinite' }} />
        ) : (
          <svg viewBox="0 0 900 280" className="w-full h-auto" role="img" aria-label="Capital flow">
            <defs>
              <marker id="ah" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto">
                <path d="M0,0 L10,5 L0,10 z" fill="currentColor" />
              </marker>
              <linearGradient id="ng" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" stopColor="#1c2a52" /><stop offset="1" stopColor="#0f1829" />
              </linearGradient>
            </defs>

            {/* flow lines */}
            <path d="M205 140 H 360" fill="none" stroke="#818cf8" strokeWidth={sw(escrowed)}
              strokeLinecap="round" strokeDasharray="11 9" markerEnd="url(#ah)" color="#818cf8"
              style={{ animation: 'flow 1.3s linear infinite' }} />
            <path d="M560 115 C 650 90, 690 55, 735 50" fill="none" stroke="#22c55e" strokeWidth={sw(released)}
              strokeLinecap="round" strokeDasharray="11 9" markerEnd="url(#ah)" color="#22c55e"
              style={{ animation: 'flow 1.3s linear infinite' }} />
            <path d="M560 165 C 650 190, 690 225, 735 232" fill="none" stroke="#14b8a6" strokeWidth={sw(recycled)}
              strokeLinecap="round" strokeDasharray="11 9" markerEnd="url(#ah)" color="#14b8a6"
              style={{ animation: 'flow 1.3s linear infinite' }} />
            <path d="M735 258 C 360 300, 115 275, 90 200" fill="none" stroke="#14b8a6" strokeWidth={Math.min(sw(recycled), 5)}
              strokeLinecap="round" strokeDasharray="7 7" opacity="0.4" markerEnd="url(#ah)" color="#14b8a6"
              style={{ animation: 'flow 1.8s linear infinite' }} />

            {/* Pool node */}
            <rect x="30" y="100" width="175" height="82" rx="14" fill="url(#ng)" stroke="#818cf8" strokeWidth="1.5" />
            <text x="117" y="128" textAnchor="middle" fill="#94a3b8" fontSize="12">Funding Pool</text>
            <text x="117" y="154" textAnchor="middle" fill="#e2e8f0" fontSize="16" fontWeight="700">{fmt(pool?.balance ?? 0n)}</text>
            <text x="117" y="173" textAnchor="middle" fill="#64748b" fontSize="10">{(pool?.apyBps ?? 0) / 100}% APY</text>

            {/* Escrow node */}
            <rect x="360" y="100" width="200" height="82" rx="14" fill="url(#ng)" stroke="#eab308" strokeWidth="1.5" />
            <text x="460" y="128" textAnchor="middle" fill="#94a3b8" fontSize="12">Agreement Escrow</text>
            <text x="460" y="154" textAnchor="middle" fill="#e2e8f0" fontSize="16" fontWeight="700">{fmt(escrowed)}</text>
            <text x="460" y="173" textAnchor="middle" fill="#64748b" fontSize="10">{active} active agreement{active !== 1 ? 's' : ''}</text>

            {/* Released node */}
            <rect x="735" y="18" width="140" height="66" rx="12" fill="url(#ng)" stroke="#22c55e" strokeWidth="1.5" />
            <text x="805" y="44" textAnchor="middle" fill="#94a3b8" fontSize="12">Released</text>
            <text x="805" y="68" textAnchor="middle" fill="#22c55e" fontSize="15" fontWeight="700">{fmt(released)}</text>

            {/* Recycled node */}
            <rect x="735" y="200" width="140" height="66" rx="12" fill="url(#ng)" stroke="#14b8a6" strokeWidth="1.5" />
            <text x="805" y="226" textAnchor="middle" fill="#94a3b8" fontSize="12">Recycled</text>
            <text x="805" y="250" textAnchor="middle" fill="#14b8a6" fontSize="15" fontWeight="700">{fmt(recycled)}</text>

            {/* Labels */}
            <text x="282" y="126" textAnchor="middle" fill="#64748b" fontSize="10">allocate</text>
            <text x="660" y="62"  textAnchor="middle" fill="#64748b" fontSize="10">proof + quorum</text>
            <text x="660" y="222" textAnchor="middle" fill="#64748b" fontSize="10">withheld</text>
            <text x="390" y="272" textAnchor="middle" fill="#64748b" fontSize="10">waterfall → next in line</text>
          </svg>
        )}
      </div>

      {/* KPI grid */}
      {isLoading ? (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          {Array(8).fill(0).map((_, i) => (
            <div key={i} className="h-20 rounded-xl"
              style={{ background: 'linear-gradient(90deg, #1e293b 25%, #334155 50%, #1e293b 75%)', backgroundSize: '200% 100%', animation: 'sk 1.2s ease infinite' }} />
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <Kpi icon="◈" label="Pool available"  value={fmt(pool?.balance ?? 0n)} />
          <Kpi icon="⬡" label="In escrow"       value={fmt(escrowed)} color="#eab308" />
          <Kpi icon="✓" label="Released"         value={fmt(released)} color="#22c55e" />
          <Kpi icon="♻" label="Recycled"         value={fmt(recycled)} color="#14b8a6" />
          <Kpi icon="★" label="Bonuses paid"     value={fmt(pool?.totalBonusesPaid ?? 0n)} color="#a78bfa" />
          <Kpi icon="◎" label="Yield reserve"    value={fmt(pool?.yieldReserve ?? 0n)} color="#f59e0b" />
          <Kpi icon="⬢" label="Active grants"    value={String(active)} />
          <Kpi icon="◐" label="APY"              value={(pool?.apyBps ?? 0) / 100 + '%'} color="#34d399" />
        </div>
      )}
    </div>
  );
}
