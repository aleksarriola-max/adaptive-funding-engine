import { useCurrentAccount, useSignAndExecuteTransaction } from '@mysten/dapp-kit';
import { Transaction } from '@mysten/sui/transactions';
import { bcs } from '@mysten/sui/bcs';
import { useState } from 'react';
import {
  PACKAGE_ID, POOL_ID, CLOCK_ID, SUI_TYPE,
  STATE_SUBMITTED, DECISION_APPROVE, DECISION_WARNING, DECISION_REJECT,
} from '../constants';
import { useAgreements, useReviewerCap } from '../hooks/useAgreements';
import { useStatus } from '../hooks/useStatus';
import StatusBanner from '../components/StatusBanner';
import Empty from '../components/Empty';
import type { AgreementData } from '../types';

function fmt(mist: bigint) { return (Number(mist) / 1e9).toFixed(4) + ' SUI'; }

const DECISIONS = [
  { value: DECISION_APPROVE, label: '✓ Approve', cls: 'bg-emerald-700 hover:bg-emerald-600' },
  { value: DECISION_WARNING, label: '⚠ Warning', cls: 'bg-amber-700 hover:bg-amber-600' },
  { value: DECISION_REJECT,  label: '✗ Reject',  cls: 'bg-red-800 hover:bg-red-700' },
];

export default function ReviewerInbox() {
  const account = useCurrentAccount();
  const { data: agreements = [], isLoading, refetch } = useAgreements();
  const { data: reviewerCap } = useReviewerCap(account?.address);
  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();
  const { status, digest, ok, err } = useStatus();
  const [voteNote, setVoteNote] = useState('');
  const [voting,   setVoting]   = useState<{ id: string; idx: number } | null>(null);

  const pending = account
    ? agreements.filter(a =>
        a.reviewers.some(r => r.toLowerCase() === account.address.toLowerCase()) &&
        a.milestones.some(m => m.state === STATE_SUBMITTED)
      )
    : [];

  function castVote(a: AgreementData, idx: number, decision: number) {
    if (!account || !reviewerCap) return;
    const tx = new Transaction();
    tx.moveCall({
      target: `${PACKAGE_ID}::agreement::cast_vote`,
      typeArguments: [SUI_TYPE],
      arguments: [
        tx.object(reviewerCap.id), tx.object(a.id), tx.object(POOL_ID),
        tx.pure.u64(BigInt(idx)),
        tx.pure.u8(decision),
        tx.pure(bcs.vector(bcs.u8()).serialize(Array.from(new TextEncoder().encode(voteNote))).toBytes()),
        tx.object(CLOCK_ID),
      ],
    });
    const label = DECISIONS.find(d => d.value === decision)?.label ?? '';
    signAndExecute({ transaction: tx }, {
      onSuccess: r => {
        ok(`Vote cast: ${label}`, r.digest);
        setVoting(null); setVoteNote('');
        setTimeout(refetch, 2000);
      },
      onError: err,
    });
  }

  if (!account) return (
    <div className="space-y-4">
      <h2 className="text-2xl font-bold">Review Inbox</h2>
      <p className="text-slate-400">Connect wallet to see pending reviews.</p>
    </div>
  );

  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-bold">Review Inbox</h2>

      {!reviewerCap && (
        <Empty
          icon="🔑"
          title="You're not a reviewer yet"
          hint="Ask the program manager to issue you a ReviewerCap — once you have one, milestone proofs awaiting your vote appear here."
        />
      )}

      {reviewerCap && (
        <div className="p-3 bg-emerald-900/30 border border-emerald-700 rounded-lg text-emerald-300 text-sm flex items-center gap-2">
          <span>✓ Reviewer cap active</span>
          <span className="font-mono text-xs opacity-70">{reviewerCap.id.slice(0, 20)}…</span>
        </div>
      )}

      {isLoading && (
        <div className="space-y-3">
          {[1].map(i => <div key={i} className="bg-slate-800 rounded-lg p-5 border border-slate-700 animate-pulse h-32" />)}
        </div>
      )}

      {!isLoading && reviewerCap && pending.length === 0 && (
        <Empty
          icon="✓"
          title="Inbox zero"
          hint="No milestone proofs are waiting on your vote right now. Check back after recipients submit their work."
        />
      )}

      {pending.map(a => (
        <div key={a.id} className="bg-slate-800 rounded-lg p-5 border border-slate-700 space-y-4">
          <div>
            <p className="text-xs font-mono text-slate-400 break-all">{a.id}</p>
            <p className="text-sm mt-1">
              Recipient: <span className="font-mono">{a.recipient.slice(0, 20)}…</span>
              {' · '}Total: <span className="text-indigo-300">{fmt(a.totalAmount)}</span>
            </p>
          </div>

          {a.milestones.map((m, idx) => {
            if (m.state !== STATE_SUBMITTED) return null;
            const isVoting = voting?.id === a.id && voting?.idx === idx;
            return (
              <div key={idx} className="bg-slate-700/40 rounded-lg p-3 space-y-3">
                <div className="flex items-center justify-between">
                  <p className="text-sm font-medium">Milestone {idx + 1} · {fmt(m.amount)}</p>
                  <span className="text-xs bg-purple-900 text-purple-300 px-2 py-0.5 rounded-full">Submitted</span>
                </div>

                {m.submissionUrl && (
                  <div className="bg-slate-700 rounded p-2 text-xs space-y-1">
                    <p className="text-slate-400">Proof URL:</p>
                    <a href={m.submissionUrl} target="_blank" rel="noreferrer"
                      className="text-indigo-400 underline break-all">{m.submissionUrl}</a>
                    {m.submissionNote && <p className="text-slate-300 mt-1">"{m.submissionNote}"</p>}
                  </div>
                )}

                {!isVoting ? (
                  <button onClick={() => setVoting({ id: a.id, idx })} disabled={!reviewerCap}
                    className="text-xs bg-indigo-700 hover:bg-indigo-600 disabled:opacity-40 rounded px-3 py-1.5">
                    Cast Vote
                  </button>
                ) : (
                  <div className="space-y-2">
                    <input
                      className="w-full bg-slate-600 rounded px-3 py-1.5 text-sm outline-none focus:ring-1 ring-indigo-500"
                      placeholder="Review note (optional)"
                      value={voteNote} onChange={e => setVoteNote(e.target.value)}
                    />
                    <div className="flex gap-2">
                      {DECISIONS.map(d => (
                        <button key={d.value} onClick={() => castVote(a, idx, d.value)} disabled={isPending}
                          className={`flex-1 disabled:opacity-40 rounded px-3 py-1.5 text-sm font-medium ${d.cls}`}>
                          {isPending ? '…' : d.label}
                        </button>
                      ))}
                    </div>
                    <button onClick={() => setVoting(null)}
                      className="text-xs text-slate-400 hover:text-slate-200">Cancel</button>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      ))}

      <StatusBanner status={status} digest={digest} />
    </div>
  );
}
