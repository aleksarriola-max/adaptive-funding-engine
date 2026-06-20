import { useSuiClientQuery } from '@mysten/dapp-kit';
import { POOL_ID } from '../constants';
import type { PoolData } from '../types';

function parseBal(v: unknown): bigint {
  if (typeof v === 'string' || typeof v === 'number' || typeof v === 'bigint') return BigInt(v);
  if (v && typeof v === 'object' && 'fields' in (v as Record<string,unknown>)) {
    const f = (v as Record<string,unknown>).fields as Record<string,unknown>;
    return BigInt((f.value as string | number) ?? 0);
  }
  return 0n;
}

export function usePool() {
  const { data, isLoading, refetch } = useSuiClientQuery('getObject', {
    id: POOL_ID,
    options: { showContent: true },
  });

  let pool: PoolData | null = null;
  if (data?.data?.content && data.data.content.dataType === 'moveObject') {
    const f = (data.data.content as { fields: Record<string, unknown> }).fields;
    pool = {
      balance:         parseBal(f.balance),
      yieldReserve:    parseBal(f.yield_reserve),
      apyBps:          Number(f.apy_bps),
      paused:          Boolean(f.paused),
      totalDeposited:  BigInt((f.total_deposited as string) ?? 0),
      totalAllocated:  BigInt((f.total_allocated as string) ?? 0),
      totalRecycled:   BigInt((f.total_recycled as string) ?? 0),
      totalBonusesPaid:BigInt((f.total_bonuses_paid as string) ?? 0),
    };
  }

  return { pool, isLoading, refetch };
}
