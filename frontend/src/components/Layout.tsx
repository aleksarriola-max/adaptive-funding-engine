import { ConnectButton, useCurrentAccount } from '@mysten/dapp-kit';
import type { ReactNode } from 'react';

const TABS = [
  { id: 'overview',  label: 'Overview' },
  { id: 'treasury',  label: 'Treasury' },
  { id: 'manager',   label: 'Manager' },
  { id: 'recipient', label: 'My Grants' },
  { id: 'reviewer',  label: 'Review Inbox' },
  { id: 'public',    label: 'Public View' },
];

interface Props {
  children: ReactNode;
  activeTab: string;
  onTabChange: (tab: string) => void;
}

export default function Layout({ children, activeTab, onTabChange }: Props) {
  const account = useCurrentAccount();

  return (
    <div className="min-h-screen bg-slate-900 text-slate-100">
      <header className="border-b border-slate-700 bg-slate-800">
        <div className="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold text-indigo-400">Adaptive Funding Engine</h1>
            <p className="text-xs text-slate-400">Sui Testnet · DeepSurge 2026</p>
          </div>
          <ConnectButton />
        </div>
        <nav className="max-w-7xl mx-auto px-4 flex gap-1">
          {TABS.map(t => (
            <button
              key={t.id}
              onClick={() => onTabChange(t.id)}
              className={`px-4 py-2 text-sm font-medium rounded-t-lg transition-colors ${
                activeTab === t.id
                  ? 'bg-slate-900 text-indigo-400 border-b-2 border-indigo-400'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              {t.label}
            </button>
          ))}
        </nav>
      </header>

      <main className="max-w-7xl mx-auto px-4 py-6">
        {!account && (
          <div className="mb-4 p-3 bg-amber-900/30 border border-amber-700 rounded-lg text-amber-300 text-sm">
            Connect your Sui wallet to interact with the protocol.
          </div>
        )}
        {children}
      </main>
    </div>
  );
}
