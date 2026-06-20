import { useSuiClient } from '@mysten/dapp-kit';
import { useQuery } from '@tanstack/react-query';
import { PACKAGE_ID } from '../constants';
import type { AgreementData } from '../types';

function parseMilestone(m: Record<string, unknown>) {
  const f = (m.fields ?? m) as Record<string, unknown>;
  const sub = f.submission
    ? (((f.submission as Record<string,unknown>).fields ?? {}) as Record<string, unknown>)
    : null;
  return {
    amount:         BigInt((f.amount as string) ?? 0),
    deadlineMs:     BigInt((f.deadline_ms as string) ?? 0),
    state:          Number(f.state ?? 0),
    withheld:       BigInt((f.withheld as string) ?? 0),
    submissionUrl:  sub ? String(sub.url ?? '') : undefined,
    submissionNote: sub ? String(sub.note ?? '') : undefined,
    submittedAtMs:  sub ? BigInt((sub.submitted_at_ms as string) ?? 0) : undefined,
  };
}

export function useAgreements() {
  const client = useSuiClient();

  return useQuery({
    queryKey: ['agreements'],
    queryFn: async (): Promise<AgreementData[]> => {
      const events = await client.queryEvents({
        query: { MoveEventType: `${PACKAGE_ID}::agreement::AgreementCreated` },
        limit: 50,
        order: 'descending',
      });

      const ids = events.data
        .map(e => (e.parsedJson as Record<string,string>)?.agreement_id)
        .filter(Boolean) as string[];

      if (ids.length === 0) return [];

      const objects = await client.multiGetObjects({
        ids,
        options: { showContent: true },
      });

      return objects
        .filter(o => o.data?.content?.dataType === 'moveObject')
        .map(o => {
          const f = (o.data!.content as { fields: Record<string, unknown> }).fields;
          const milestones = (f.milestones as Record<string, unknown>[]) ?? [];
          return {
            id:               o.data!.objectId,
            programId:        String(f.program_id),
            poolId:           String(f.pool_id),
            recipient:        String(f.recipient),
            reviewers:        (f.reviewers as string[]) ?? [],
            quorumThreshold:  BigInt((f.quorum_threshold as string) ?? 1),
            milestones:       milestones.map(parseMilestone),
            totalAmount:      BigInt((f.total_amount as string) ?? 0),
            releasedTotal:    BigInt((f.released_total as string) ?? 0),
            paused:           Boolean(f.paused),
            active:           Boolean(f.active),
          };
        });
    },
    refetchInterval: 10_000,
  });
}

export function useReviewerCap(address: string | undefined) {
  const client = useSuiClient();

  return useQuery({
    queryKey: ['reviewerCap', address],
    queryFn: async () => {
      if (!address) return null;
      const objects = await client.getOwnedObjects({
        owner: address,
        filter: { StructType: `${PACKAGE_ID}::program::ReviewerCap` },
        options: { showContent: true },
      });
      const cap = objects.data[0];
      if (!cap?.data?.content || cap.data.content.dataType !== 'moveObject') return null;
      const f = (cap.data.content as { fields: Record<string, unknown> }).fields;
      return {
        id:        cap.data.objectId,
        programId: String(f.program_id),
        reviewer:  String(f.reviewer),
      };
    },
    enabled: !!address,
    refetchInterval: 15_000,
  });
}
