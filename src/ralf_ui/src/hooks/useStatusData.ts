import { useQuery } from '@tanstack/react-query';
import { fetchStatusSnapshot, StatusSnapshot } from '../api/status';

export const useStatusData = () => {
  return useQuery<StatusSnapshot, Error>({
    queryKey: ['status-snapshot'],
    queryFn: fetchStatusSnapshot,
    refetchInterval: 30_000
  });
};
