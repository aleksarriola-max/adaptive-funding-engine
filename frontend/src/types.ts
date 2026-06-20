export interface PoolData {
  balance: bigint;
  yieldReserve: bigint;
  apyBps: number;
  paused: boolean;
  totalDeposited: bigint;
  totalAllocated: bigint;
  totalRecycled: bigint;
  totalBonusesPaid: bigint;
}

export interface MilestoneData {
  amount: bigint;
  deadlineMs: bigint;
  state: number;
  withheld: bigint;
  submissionUrl?: string;
  submissionNote?: string;
  submittedAtMs?: bigint;
}

export interface AgreementData {
  id: string;
  programId: string;
  poolId: string;
  recipient: string;
  reviewers: string[];
  quorumThreshold: bigint;
  milestones: MilestoneData[];
  totalAmount: bigint;
  releasedTotal: bigint;
  paused: boolean;
  active: boolean;
}
