import { useCurrentAccount, useSignAndExecuteTransaction } from '@mysten/dapp-kit';
import { Transaction } from '@mysten/sui/transactions';
import { bcs } from '@mysten/sui/bcs';
import { useState } from 'react';
import {
  PACKAGE_ID, CLOCK_ID, SUI_TYPE,
  STATE_OPEN, STATE_SUBMITTED, STATE_STREAMING, STATE_PAID, STATE_RECYCLED,
} from '../constants';
import { useAgreements } from '../hooks/useAgreements';
import { useStatus } from '../hooks/useStatus';
import StatusBanner from '../components/StatusBanner';
import Empty from '../components/Empty';
import type { AgreementData } from '../types';

function fmt(mist: bigint) { return (Number(mist) / 1e9).toFixed(4) + ' SUI'; }
function fmtDate(ms: bigint) { return new Date(Number(ms)).toLocaleDateString(); }

function encodeBytes(text: string): Uint8Array {
  return bcs.vector(bcs.u8()).serialize(Array.from(new TextEncoder().encode(text))).toBytes();
}

const STATE_STYLE: Record<number, string> = {
  0: 'bg-slate-600 text-slate-300',
  1: 'bg-amber-900 text-amber-300',
  2: 'bg-purple-900 text-purple-300',
  3: 'bg-blue-900 text-blue-300',
  4: 'bg-emerald-900 text-emerald-300',
  5: 'bg-teal-900 text-teal-300',
  6: 'bg-red-900 text-red-300',
  7: 'bg-slate-700 text-slate-400',
  8: 'bg-slate-700 text-slate-400',
};
const STATE_LABEL: Record<number, string> = {
  0:'Locked', 1:'Open', 2:'Submitted', 3:'Streaming',
  4:'Paid', 5:'Partial', 6:'Rejected', 7:'Expired', 8:'Recycled',
};

export default function RecipientPortal() {
  const account = useCurrentAccount();
  const { data: agreements = [], isLoading, refetch } = useAgreements();
  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();
  const { status, digest, ok, err } = useStatus();

  const [submitting, setSubmitting] = useState<{ id: string; idx: number } | null>(null);
  const [proofUrl,   setProofUrl]   = useState('');
  const [proofNote,  setProofNote]  = useState('');

  const myAgreements = account
    ? agreements.filter(a => a.recipient.toLowerCase() === account.address.toLowerCase())
    : [];

  function submitProof(a: AgreementData, idx: number) {
    if (!account) return;
    const tx = new Transaction();
    tx.moveCall({
      target: `${PACKAGE_ID}::agreement::submit_proof`,
      typeArguments: [SUI_TYPE],
      arguments: [
        tx.object(a.id),
        tx.pure.u64(BigInt(idx)),
        tx.pure(encodeBytes(proofUrl || 'https://proof.example')),
        tx.pure(bcs.vector(bcs.u8()).serialize(new Array(32).fill(0)).toBytes()),
        tx.pure(encodeBytes(proofNote || '')),
        tx.object(CLOCK_ID),
      ],
    });
    signAndExecute({ transaction: tx }, {
      onSuccess: r => {
        ok('Proof submitted! Awaiting reviewer votes.', r.digest);
        setSubmitting(null); setProofUrl(''); setProofNote('');
        setTimeout(refetch, 2000);
      },
      onError: err,
    });
  }

  function claimVested(a: AgreementData, idx: number) {
    if (!account) return;
    const tx = new Transaction();
    tx.moveCall({
      target: `${PACKAGE_ID}::agreement::claim_vested`,
      typeArguments: [SUI_TYPE],
      arguments: [tx.object(a.id), tx.pure.u64(BigInt(idx)), tx.object(CLOCK_ID)],
    });
    signAndExecute({ transaction: tx }, {
      onSuccess: r => { ok('Funds claimed!', r.digest); setTimeout(refetch, 2000); },
      onError: err,
    });
  }

  function complete(a: AgreementData) {
    if (!account) return;
    const tx = new Transaction();
    tx.moveCall({
      target: `${PACKAGE_ID}::agreement::complete_agreement`,
      typeArguments: [SUI_TYPE],
      arguments: [tx.object(a.id)],
    });
    signAndExecute({ transaction: tx }, {
      onSuccess: r => { ok('Agreement complete! Soulbound credential minted.', r.digest); setTimeout(refetch, 2000); },
      onError: err,
    });
  }

  if (!account) return (
    <div className="space-y-4">
      <h2 className="text-2xl font-bold">My Grants</h2>
      <p className="text-slate-400">Connect wallet to view your grants.</p>
    </div>
  );

  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-bold">My Grants</h2>

      {isLoading && (
        <div className="space-y-3">
          {[1,2].map(i => <div key={i} className="bg-slate-800 rounded-lg p-5 border border-slate-700 animate-pulse h-40" />)}
        </div>
      )}

      {!isLoading && myAgreements.length === 0 && (
        <Empty
          icon="📭"
          title="No active awards"
          hint="When a manager funds an agreement to your wallet address, it shows up here."
        />
      )}

      {myAgreements.map(a => {
        const allTerminal = a.milestones.every(m => m.state === STATE_PAID || m.state === STATE_RECYCLED);
        return (
          <div key={a.id} className="bg-slate-800 rounded-lg p-5 border border-slate-700 space-y-4">
            <div className="flex items-start justify-between">
              <div>
                <p className="text-xs font-mono text-slate-400 break-all">{a.id}</p>
                <p className="text-sm mt-1">
                  Total: <span className="text-indigo-300 font-semibold">{fmt(a.totalAmount)}</span>
                  {' · '}Released: <span className="text-emerald-300">{fmt(a.releasedTotal)}</span>
                </p>
              </div>
              <span className={`shrink-0 ml-3 text-xs px-2 py-1 rounded-full ${a.active ? 'bg-emerald-900 text-emerald-300' : 'bg-indigo-900 text-indigo-300'}`}>
                {a.active ? 'Active' : '✓ Completed'}
              </span>
            </div>

            {a.milestones.map((m, idx) => {
              const isSubmitting = submitting?.id === a.id && submitting?.idx === idx;
              return (
                <div key={idx} className="bg-slate-700/40 rounded-lg p-3 space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-medium">Milestone {idx + 1} · {fmt(m.amount)}</span>
                    <span className={`text-xs px-2 py-0.5 rounded-full ${STATE_STYLE[m.state] ?? ''}`}>
                      {STATE_LABEL[m.state] ?? m.state}
                    </span>
                  </div>
                  <p className="text-xs text-slate-400">Deadline: {fmtDate(m.deadlineMs)}</p>

                  {m.submissionUrl && (
                    <p className="text-xs text-slate-400">
                      Proof: <a href={m.submissionUrl} target="_blank" rel="noreferrer"
                        className="text-indigo-400 underline">{m.submissionUrl}</a>
                    </p>
                  )}

                  {m.state === STATE_OPEN && !isSubmitting && (
                    <button onClick={() => setSubmitting({ id: a.id, idx })}
                      className="text-xs bg-amber-700 hover:bg-amber-600 rounded px-3 py-1.5">
                      Submit Proof
                    </button>
                  )}

                  {m.state === STATE_OPEN && isSubmitting && (
                    <div className="space-y-2 pt-1">
                      <input className="w-full bg-slate-600 rounded px-3 py-1.5 text-sm outline-none focus:ring-1 ring-indigo-500"
                        placeholder="Proof URL (https://… or ipfs://…)"
                        value={proofUrl} onChange={e => setProofUrl(e.target.value)} />
                      <input className="w-full bg-slate-600 rounded px-3 py-1.5 text-sm outline-none focus:ring-1 ring-indigo-500"
                        placeholder="Note (optional)"
                        value={proofNote} onChange={e => setProofNote(e.target.value)} />
                      <div className="flex gap-2">
                        <button onClick={() => submitProof(a, idx)} disabled={isPending}
                          className="flex-1 bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 rounded px-3 py-1.5 text-sm">
                          {isPending ? 'Confirming…' : 'Submit'}
                        </button>
                        <button onClick={() => setSubmitting(null)}
                          className="px-3 py-1.5 text-sm text-slate-400 hover:text-slate-200">
                          Cancel
                        </button>
                      </div>
                    </div>
                  )}

                  {m.state === STATE_SUBMITTED && (
                    <p className="text-xs text-purple-300">⏳ Awaiting reviewer votes…</p>
                  )}

                  {m.state === STATE_STREAMING && (
                    <div className="space-y-1">
                      <p className="text-xs text-blue-300">Funds are vesting — claim what's unlocked so far.</p>
                      <button onClick={() => claimVested(a, idx)} disabled={isPending}
                        className="text-xs bg-blue-700 hover:bg-blue-600 disabled:opacity-40 rounded px-3 py-1.5">
                        {isPending ? 'Confirming…' : 'Claim Vested Funds'}
                      </button>
                    </div>
                  )}
                </div>
              );
            })}

            {a.active && allTerminal && (
              <button onClick={() => complete(a)} disabled={isPending}
                className="bg-emerald-700 hover:bg-emerald-600 disabled:opacity-40 rounded px-4 py-2 text-sm font-medium">
                {isPending ? 'Confirming…' : 'Complete Agreement & Mint Credential'}
              </button>
            )}
          </div>
        );
      })}

      <StatusBanner status={status} digest={digest} />
    </div>
  );
}
