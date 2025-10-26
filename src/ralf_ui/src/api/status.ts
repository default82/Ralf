export type ServiceStatus = {
  name: string;
  category: 'database' | 'automation' | 'monitoring' | 'communication' | 'core';
  healthy: boolean;
  latency_ms?: number;
  incidents?: number;
};

export type StatusSnapshot = {
  generatedAt: string;
  inventoryTotals: {
    hosts: number;
    services: number;
    alertsOpen: number;
  };
  services: ServiceStatus[];
  matrixRooms: {
    room: string;
    bot: string;
    active: boolean;
  }[];
};

const parseSnapshot = async (response: Response): Promise<StatusSnapshot> => {
  if (!response.ok) {
    throw new Error(`API responded with ${response.status}`);
  }

  const payload = await response.json();

  if (payload.data?.statusSnapshot) {
    return payload.data.statusSnapshot as StatusSnapshot;
  }

  if (payload.snapshot) {
    return payload.snapshot as StatusSnapshot;
  }

  return payload as StatusSnapshot;
};

const fallbackSnapshot: StatusSnapshot = {
  generatedAt: new Date().toISOString(),
  inventoryTotals: {
    hosts: 0,
    services: 0,
    alertsOpen: 0
  },
  services: [],
  matrixRooms: []
};

export const fetchStatusSnapshot = async (): Promise<StatusSnapshot> => {
  const restEndpoint = import.meta.env.VITE_STATUS_API_URL;
  const graphQLEndpoint = import.meta.env.VITE_STATUS_GRAPHQL_URL;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);

  try {
    if (graphQLEndpoint) {
      const response = await fetch(graphQLEndpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          query: `
            query StatusSnapshot {
              statusSnapshot {
                generatedAt
                inventoryTotals { hosts services alertsOpen }
                services { name category healthy latency_ms incidents }
                matrixRooms { room bot active }
              }
            }
          `
        }),
        signal: controller.signal
      });

      clearTimeout(timeout);
      return parseSnapshot(response);
    }

    if (!restEndpoint) {
      console.warn('No REST or GraphQL endpoint configured for status data.');
      return fallbackSnapshot;
    }

    const response = await fetch(restEndpoint, {
      headers: {
        Accept: 'application/json'
      },
      signal: controller.signal
    });
    clearTimeout(timeout);
    return parseSnapshot(response);
  } catch (error) {
    if ((error as Error).name === 'AbortError') {
      console.warn('Status snapshot request timed out');
    } else {
      console.error('Failed to load status snapshot', error);
    }
    return fallbackSnapshot;
  }
};
