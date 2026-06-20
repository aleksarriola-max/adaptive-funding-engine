import { useCurrentAccount, useSignAndExecuteTransaction } from '@mysten/dapp-kit';
import { Transaction } from '@mysten/sui/transactions';
import { useState } from 'react';
import { PACKAGE_ID, POOL_ID, CLOCK_ID, SUI_TYPE } from '../constants';
import { usePool } from '../hooks/usePool';
import { useStatus } from '../hooks/useStatus';
import StatusBanner from '../components/StatusBanner';

function fmt(mist: bigint) {
  return (Number(mist) / 1e9).toFixed(4) + ' SUI';
}

function suiToMist(s: string): bigint {
  return BigInt(Math.floor(parseFloat(s) * 1e9));
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-slate-800 rounded-lg p-4 border border-slate-700">
      <p className="text-xs text-slate-400 mb-1">{label}</p>
      <p className="text-lg font-semibold text-indigo-300">{value}</p>
    </div>
  );
}

export default function Treasury() {
  const account = useCurrentAccount();
  const { pool, isLoading, refetch } = usePool();
  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();
  const { status, digest, ok, err } = useStatus();
  const [depositAmt, setDepositAmt] = useState('');
  const [yieldAmt,   setYieldAmt]   = useState('');

  function deposit() {
    if (!account || !depositAmt) return;
    const tx = new Transaction();
    const [coin] = tx.splitCoins(tx.gas, [tx.pure.u64(suiToMist(depositAmt))]);
    tx.moveCall({
      target: `${PACKAGE_ID}::pool::deposit`,
      typeArguments: [SUI_TYPE],
      arguments: [tx.object(POOL_ID), coin],
    });
    signAndExecute({ transaction: tx }, {
      onSuccess: r => { ok('Deposited!', r.digest); setDepositAmt(''); refetch(); },
      onError: err,
    });
  }

  function depositYield() {
    if (!account || !yieldAmt) return;
    const tx = new Transaction();
    const [coin] = tx.splitCoins(tx.gas, [tx.pure.u64(suiToMist(yieldAmt))]);
    tx.moveCall({
      target: `${PACKAGE_ID}::pool::deposit_yield_reserve`,
      typeArguments: [SUI_TYPE],
      arguments: [tx.object(POOL_ID), coin],
    });
    signAndExecute({ transaction: tx }, {
      onSuccess: r => { ok('Yield reserve funded!', r.digest); setYieldAmt(''); refetch(); },
      onError: err,
    });
  }

  function accrueYield() {
    if (!account) return;
    const tx = new Transaction();
    tx.moveCall({
      target: `${PACKAGE_ID}::pool::accrue_yield`,
      typeArguments: [SUI_TYPE],
      arguments: [tx.object(POOL_ID), tx.object(CLOCK_ID)],
    });
    signAndExecute({ transaction: tx }, {
      onSuccess: r => { ok('Yield accrued!', r.digest); refetch(); },
      onError: err,
    });
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-bold">Treasury</h2>
        <button onClick={() => refetch()}
          className="text-xs text-slate-400 hover:text-slate-200 border border-slate-700 rounded px-3 py-1.5 transition-colors">
          ↻ Refresh
        </button>
      </div>

      {isLoading && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {Array(8).fill(0).map((_, i) => (
            <div key={i} className="bg-slate-800 rounded-lg p-4 border border-slate-700 animate-pulse h-20" />
          ))}
        </div>
      )}

      {pool && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <StatCard label="Available Balance"  value={fmt(pool.balance)} />
          <StatCard label="Yield Reserve"      value={fmt(pool.yieldReserve)} />
          <StatCard label="APY"                value={(pool.apyBps / 100).toFixed(2) + '%'} />
          <StatCard label="Status"             value={pool.paused ? '⏸ Paused' : '▶ Active'} />
          <StatCard label="Total Deposited"    value={fmt(pool.totalDeposited)} />
          <StatCard label="Total Allocated"    value={fmt(pool.totalAllocated)} />
          <StatCard label="Total Recycled"     value={fmt(pool.totalRecycled)} />
          <StatCard label="Bonuses Paid"       value={fmt(pool.totalBonusesPaid)} />
        </div>
      )}

      <div className="grid md:grid-cols-3 gap-4">
        <div className="bg-slate-800 rounded-lg p-4 border border-slate-700 space-y-3">
          <h3 className="font-semibold">Deposit SUI</h3>
          <input
            type="number" min="0" step="0.1" placeholder="Amount (SUI)"
            value={depositAmt} onChange={e => setDepositAmt(e.target.value)}
            className="w-full bg-slate-700 rounded px-3 py-2 text-sm outline-none focus:ring-2 ring-indigo-500"
          />
          <button onClick={deposit} disabled={isPending || !account || !depositAmt}
            className="w-full bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 rounded px-4 py-2 text-sm font-medium transition-colors">
            {isPending ? 'Confirming…' : 'Deposit'}
          </button>
        </div>

        <div className="bg-slate-800 rounded-lg p-4 border border-slate-700 space-y-3">
          <h3 className="font-semibold">Fund Yield Reserve</h3>
          <input
            type="number" min="0" step="0.1" placeholder="Amount (SUI)"
            value={yieldAmt} onChange={e => setYieldAmt(e.target.value)}
            className="w-full bg-slate-700 rounded px-3 py-2 text-sm outline-none focus:ring-2 ring-indigo-500"
          />
          <button onClick={depositYield} disabled={isPending || !account || !yieldAmt}
            className="w-full bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 rounded px-4 py-2 text-sm font-medium transition-colors">
            {isPending ? 'Confirming…' : 'Fund Reserve'}
          </button>
        </div>

        <div className="bg-slate-800 rounded-lg p-4 border border-slate-700 space-y-3">
          <h3 className="font-semibold">Accrue Yield</h3>
          <p className="text-xs text-slate-400">Transfers earned APY from reserve to main balance based on elapsed time.</p>
          <button onClick={accrueYield} disabled={isPending || !account}
            className="w-full bg-emerald-700 hover:bg-emerald-600 disabled:opacity-40 rounded px-4 py-2 text-sm font-medium transition-colors">
            {isPending ? 'Confirming…' : 'Accrue Yield'}
          </button>
        </div>
      </div>

      <StatusBanner status={status} digest={digest} />
    </div>
  );
}
