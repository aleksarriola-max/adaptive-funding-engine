import { useCurrentAccount, useSignAndExecuteTransaction } from '@mysten/dapp-kit';
import { Transaction } from '@mysten/sui/transactions';
import { bcs } from '@mysten/sui/bcs';
import { useState, type ReactNode } from 'react';
import Celebrate from '../components/Celebrate';
import {
  PACKAGE_ID, POOL_ID, MANAGER_CAP_ID, WAITLIST_ID, CLOCK_ID, SUI_TYPE,
  REVIEWER_1_ADDR, REVIEWER_2_ADDR,
  CURVE_LINEAR, CURVE_STEPPED, CURVE_ACCELERATING,
  MS_PER_DAY,
} from '../constants';
import { useStatus } from '../hooks/useStatus';
import StatusBanner from '../components/StatusBanner';

function suiToMist(s: string): bigint {
  return BigInt(Math.floor(parseFloat(s || '0') * 1e9));
}

function addrToBytes(addr: string): number[] {
  const hex = addr.replace('0x', '').padStart(64, '0');
  return Array.from({ length: 32 }, (_, i) => parseInt(hex.slice(i * 2, i * 2 + 2), 16));
}

function encodeAddressVec(addrs: string[]): Uint8Array {
  const buf: number[] = [];
  let len = addrs.length;
  do { let b = len & 0x7f; len >>= 7; if (len > 0) b |= 0x80; buf.push(b); } while (len > 0);
  for (const a of addrs) buf.push(...addrToBytes(a));
  return new Uint8Array(buf);
}

function encodeU64Vec(values: bigint[]): Uint8Array {
  return bcs.vector(bcs.u64()).serialize(values).toBytes();
}

function encodeBytes(text: string): Uint8Array {
  return bcs.vector(bcs.u8()).serialize(Array.from(new TextEncoder().encode(text))).toBytes();
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="bg-slate-800 rounded-lg p-5 border border-slate-700 space-y-3">
      <h3 className="font-semibold text-lg border-b border-slate-700 pb-2">{title}</h3>
      {children}
    </div>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <label className="block text-xs text-slate-400 mb-1">{label}</label>
      {children}
    </div>
  );
}

function Input({ label, ...props }: { label: string } & React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <Field label={label}>
      <input {...props}
        className="w-full bg-slate-700 rounded px-3 py-2 text-sm outline-none focus:ring-2 ring-indigo-500" />
    </Field>
  );
}

function Btn({ onClick, disabled, color = 'indigo', loading, children }: {
  onClick: () => void; disabled?: boolean; color?: 'indigo'|'amber'|'emerald'; loading?: boolean; children: ReactNode;
}) {
  const cls = { indigo: 'bg-indigo-600 hover:bg-indigo-500', amber: 'bg-amber-700 hover:bg-amber-600', emerald: 'bg-emerald-700 hover:bg-emerald-600' }[color];
  return (
    <button onClick={onClick} disabled={disabled}
      className={`w-full ${cls} disabled:opacity-40 rounded px-4 py-2 text-sm font-medium transition-colors`}>
      {loading ? 'Confirming…' : children}
    </button>
  );
}

export default function ManagerDashboard() {
  const account = useCurrentAccount();
  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();
  const { status, digest, ok, err } = useStatus();
  const dis = isPending || !account;

  const [reviewerAddr, setReviewerAddr] = useState('');
  const [recipient,   setRecipient]   = useState('');
  const [reviewers,   setReviewers]   = useState(`${REVIEWER_1_ADDR},${REVIEWER_2_ADDR}`);
  const [quorum,      setQuorum]      = useState('1');
  const [m1Amt,       setM1Amt]       = useState('0.5');
  const [m2Amt,       setM2Amt]       = useState('0.5');
  const [m1Days,      setM1Days]      = useState('30');
  const [m2Days,      setM2Days]      = useState('60');
  const [streamDays,  setStreamDays]  = useState('7');
  const [cliffDays,   setCliffDays]   = useState('0');
  const [curve,       setCurve]       = useState(String(CURVE_LINEAR));
  const [bonusBps,    setBonusBps]    = useState('500');
  const [lateDecay,   setLateDecay]   = useState('100');
  const [reviewDays,  setReviewDays]  = useState('3');
  const [wlRecipient,   setWlRecipient]   = useState('');
  const [wlAmount,      setWlAmount]      = useState('1');
  const [wlDescription, setWlDescription] = useState('');
  const [celebrate, setCelebrate] = useState<{ title: string; sub: string } | null>(null);

  function issueReviewer() {
    if (!account || !reviewerAddr.trim()) return;
    const tx = new Transaction();
    tx.moveCall({
      target: `${PACKAGE_ID}::program::issue_reviewer_cap`,
      arguments: [tx.object(MANAGER_CAP_ID), tx.pure.address(reviewerAddr.trim())],
    });
    signAndExecute({ transaction: tx }, {
      onSuccess: r => { ok('ReviewerCap issued!', r.digest); setReviewerAddr(''); },
      onError: err,
    });
  }

  function createAgreement() {
    if (!account || !recipient.trim()) return;
    const tx = new Transaction();
    const now = BigInt(Date.now());
    const reviewerList = reviewers.split(',').map(a => a.trim()).filter(Boolean);
    tx.moveCall({
      target: `${PACKAGE_ID}::agreement::create_agreement`,
      typeArguments: [SUI_TYPE],
      arguments: [
        tx.object(MANAGER_CAP_ID), tx.object(POOL_ID),
        tx.pure.address(recipient.trim()),
        tx.pure(encodeAddressVec(reviewerList)),
        tx.pure.u64(BigInt(quorum)),
        tx.pure(encodeU64Vec([suiToMist(m1Amt), suiToMist(m2Amt)])),
        tx.pure(encodeU64Vec([now + BigInt(parseInt(m1Days)) * BigInt(MS_PER_DAY),
                               now + BigInt(parseInt(m2Days)) * BigInt(MS_PER_DAY)])),
        tx.pure.u64(BigInt(parseInt(streamDays)) * BigInt(MS_PER_DAY)),
        tx.pure.u64(BigInt(parseInt(cliffDays))  * BigInt(MS_PER_DAY)),
        tx.pure.u8(Number(curve)),
        tx.pure.u64(BigInt(bonusBps)),
        tx.pure.u64(BigInt(lateDecay)),
        tx.pure.u64(BigInt(parseInt(reviewDays)) * BigInt(MS_PER_DAY)),
        tx.object(CLOCK_ID),
      ],
    });
    signAndExecute({ transaction: tx }, {
      onSuccess: r => ok('Agreement created!', r.digest),
      onError: err,
    });
  }

  function addToWaitlist() {
    if (!account || !wlRecipient.trim()) return;
    const tx = new Transaction();
    tx.moveCall({
      target: `${PACKAGE_ID}::agreement::add_to_waitlist`,
      typeArguments: [SUI_TYPE],
      arguments: [
        tx.object(MANAGER_CAP_ID), tx.object(WAITLIST_ID),
        tx.pure.address(wlRecipient.trim()),
        tx.pure.u64(suiToMist(wlAmount)),
        tx.pure(encodeAddressVec([REVIEWER_1_ADDR, REVIEWER_2_ADDR])),
        tx.pure.u64(1n),
        tx.pure.u64(BigInt(7 * MS_PER_DAY)),
        tx.pure.u64(BigInt(1 * MS_PER_DAY)),
        tx.pure.u8(CURVE_LINEAR),
        tx.pure.u64(500n), tx.pure.u64(100n),
        tx.pure.u64(BigInt(3 * MS_PER_DAY)),
        tx.pure(encodeBytes(wlDescription)),
      ],
    });
    signAndExecute({ transaction: tx }, {
      onSuccess: r => { ok('Added to waitlist!', r.digest); setWlRecipient(''); setWlDescription(''); },
      onError: err,
    });
  }

  function tryFundNext() {
    if (!account) return;
    const tx = new Transaction();
    tx.moveCall({
      target: `${PACKAGE_ID}::agreement::try_fund_next`,
      typeArguments: [SUI_TYPE],
      arguments: [tx.object(MANAGER_CAP_ID), tx.object(WAITLIST_ID), tx.object(POOL_ID), tx.object(CLOCK_ID)],
    });
    signAndExecute({ transaction: tx }, {
      onSuccess: r => {
        ok('Funded next from waitlist!', r.digest);
        setCelebrate({ title: 'Capital re-routed!', sub: 'Withheld funds returned to the pool and funded the next recipient — in one transaction.' });
      },
      onError: err,
    });
  }

  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-bold">Manager Dashboard</h2>
      <p className="text-xs text-slate-400">
        Connected wallet must hold the ManagerCap to execute these actions.
      </p>

      <div className="grid md:grid-cols-2 gap-6">
        <Section title="Issue Reviewer Cap">
          <Input label="Reviewer wallet address" placeholder="0x…"
            value={reviewerAddr} onChange={e => setReviewerAddr(e.target.value)} />
          <Btn onClick={issueReviewer} disabled={dis || !reviewerAddr} loading={isPending}>Issue Cap</Btn>
        </Section>

        <Section title="Create Funding Agreement">
          <p className="text-xs text-slate-500 -mt-1">Allocate capital once; the state machine governs every coin after.</p>
          <Input label="Recipient address" placeholder="0x…"
            value={recipient} onChange={e => setRecipient(e.target.value)} />
          <Input label="Reviewers (comma-separated)"
            value={reviewers} onChange={e => setReviewers(e.target.value)} />
          <div className="grid grid-cols-2 gap-3">
            <Input label="Milestone 1 (SUI)" type="number" value={m1Amt}  onChange={e => setM1Amt(e.target.value)} />
            <Input label="M1 deadline (days)" type="number" value={m1Days} onChange={e => setM1Days(e.target.value)} />
            <Input label="Milestone 2 (SUI)" type="number" value={m2Amt}  onChange={e => setM2Amt(e.target.value)} />
            <Input label="M2 deadline (days)" type="number" value={m2Days} onChange={e => setM2Days(e.target.value)} />
          </div>
          <details className="border border-slate-700 rounded-lg bg-slate-700/30">
            <summary className="cursor-pointer px-3 py-2 text-xs text-slate-400 hover:text-slate-200 select-none">
              Advanced policy (vesting, bonus, penalties, timeout)
            </summary>
            <div className="px-3 pb-3 pt-1 grid grid-cols-2 gap-3">
              <Input label="Quorum (# votes)" type="number" value={quorum} onChange={e => setQuorum(e.target.value)} />
              <Field label="Vesting Curve">
                <select value={curve} onChange={e => setCurve(e.target.value)}
                  className="w-full bg-slate-700 rounded px-3 py-2 text-sm outline-none focus:ring-2 ring-indigo-500">
                  <option value={CURVE_LINEAR}>Linear</option>
                  <option value={CURVE_STEPPED}>Stepped (4×25%)</option>
                  <option value={CURVE_ACCELERATING}>Accelerating</option>
                </select>
              </Field>
              <Input label="Stream duration (days)"  type="number" value={streamDays} onChange={e => setStreamDays(e.target.value)} />
              <Input label="Cliff (days)"            type="number" value={cliffDays}  onChange={e => setCliffDays(e.target.value)} />
              <Input label="Bonus bps (500=5%)"      type="number" value={bonusBps}   onChange={e => setBonusBps(e.target.value)} />
              <Input label="Late decay (bps/day)"    type="number" value={lateDecay}  onChange={e => setLateDecay(e.target.value)} />
              <div className="col-span-2">
                <Input label="Review timeout (days)" type="number" value={reviewDays} onChange={e => setReviewDays(e.target.value)} />
              </div>
            </div>
          </details>
          <Btn onClick={createAgreement} disabled={dis || !recipient} loading={isPending}>Create Agreement</Btn>
        </Section>

        <Section title="Add to Waitlist">
          <Input label="Recipient address" placeholder="0x…"
            value={wlRecipient} onChange={e => setWlRecipient(e.target.value)} />
          <Input label="Amount (SUI)" type="number" value={wlAmount} onChange={e => setWlAmount(e.target.value)} />
          <Input label="Description" placeholder="e.g. Grace Hopper CS Scholarship"
            value={wlDescription} onChange={e => setWlDescription(e.target.value)} />
          <Btn onClick={addToWaitlist} disabled={dis || !wlRecipient} loading={isPending} color="amber">Add to Waitlist</Btn>
        </Section>

        <Section title="Fund from Waitlist">
          <p className="text-sm text-slate-400">
            Dequeues the next entry and creates a live agreement if the pool balance is sufficient.
          </p>
          <Btn onClick={tryFundNext} disabled={dis} loading={isPending} color="emerald">Fund Next in Queue</Btn>
        </Section>
      </div>

      <StatusBanner status={status} digest={digest} />

      <Celebrate
        show={!!celebrate}
        title={celebrate?.title ?? ''}
        sub={celebrate?.sub ?? ''}
        onDone={() => setCelebrate(null)}
      />
    </div>
  );
}
