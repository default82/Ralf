import { Fragment } from 'react';
import { useStatusData } from '../hooks/useStatusData';

const StatusDashboard = () => {
  const { data, isLoading, error, isFetching } = useStatusData();

  return (
    <div className="flex flex-col gap-6">
      <section className="grid gap-4 sm:grid-cols-3">
        <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4">
          <p className="text-xs uppercase tracking-widest text-slate-400">Hosts</p>
          <p className="mt-2 text-3xl font-semibold text-white">
            {data?.inventoryTotals.hosts ?? '–'}
          </p>
        </div>
        <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4">
          <p className="text-xs uppercase tracking-widest text-slate-400">Services</p>
          <p className="mt-2 text-3xl font-semibold text-white">
            {data?.inventoryTotals.services ?? '–'}
          </p>
        </div>
        <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4">
          <p className="text-xs uppercase tracking-widest text-slate-400">Offene Alerts</p>
          <p
            className={`mt-2 text-3xl font-semibold ${
              (data?.inventoryTotals.alertsOpen ?? 0) > 0
                ? 'text-amber-300'
                : 'text-emerald-300'
            }`}
          >
            {data?.inventoryTotals.alertsOpen ?? '–'}
          </p>
        </div>
      </section>

      <section className="rounded-xl border border-slate-800 bg-slate-900/60">
        <div className="flex items-center justify-between border-b border-slate-800 px-6 py-4">
          <div>
            <h2 className="text-lg font-semibold text-white">Service-Gesundheit</h2>
            <p className="text-sm text-slate-400">
              Echtzeitdaten aus PostgreSQL, aggregiert via Ralf-Core API.
            </p>
          </div>
          <div className="flex items-center gap-3 text-xs text-slate-400">
            {isFetching && <span className="animate-pulse text-brand">aktualisiere…</span>}
            {data?.generatedAt && (
              <span>Stand: {new Date(data.generatedAt).toLocaleString()}</span>
            )}
          </div>
        </div>
        <div className="px-6 py-4">
          {isLoading && <p className="text-sm text-slate-400">Lade Status…</p>}
          {error && (
            <p className="text-sm text-rose-300">
              Fehler beim Laden der Daten: {error.message}
            </p>
          )}
          {!isLoading && !error && (
            <div className="grid gap-4 md:grid-cols-2">
              {data?.services.length ? (
                data.services.map((service) => (
                  <article
                    key={service.name}
                    className="rounded-lg border border-slate-800 bg-slate-900/80 p-4"
                  >
                    <header className="flex items-center justify-between">
                      <div>
                        <h3 className="text-base font-semibold text-white">
                          {service.name}
                        </h3>
                        <p className="text-xs uppercase tracking-widest text-slate-400">
                          {service.category}
                        </p>
                      </div>
                      <span
                        className={`rounded-full px-3 py-1 text-xs font-semibold uppercase ${
                          service.healthy
                            ? 'bg-emerald-500/10 text-emerald-300'
                            : 'bg-rose-500/10 text-rose-300'
                        }`}
                      >
                        {service.healthy ? 'healthy' : 'issue'}
                      </span>
                    </header>
                    <dl className="mt-3 grid grid-cols-2 gap-2 text-xs text-slate-300">
                      {service.latency_ms != null && (
                        <div>
                          <dt className="uppercase tracking-widest text-slate-500">
                            Latenz
                          </dt>
                          <dd className="text-sm font-medium text-white">
                            {service.latency_ms} ms
                          </dd>
                        </div>
                      )}
                      {service.incidents != null && (
                        <div>
                          <dt className="uppercase tracking-widest text-slate-500">
                            Incidents
                          </dt>
                          <dd
                            className={`text-sm font-medium ${
                              service.incidents > 0 ? 'text-amber-300' : 'text-emerald-300'
                            }`}
                          >
                            {service.incidents}
                          </dd>
                        </div>
                      )}
                    </dl>
                  </article>
                ))
              ) : (
                <p className="text-sm text-slate-400">
                  Keine Service-Daten verfügbar. Bitte API-Verbindung prüfen.
                </p>
              )}
            </div>
          )}
        </div>
      </section>

      <section className="rounded-xl border border-slate-800 bg-slate-900/60">
        <div className="flex items-center justify-between border-b border-slate-800 px-6 py-4">
          <div>
            <h2 className="text-lg font-semibold text-white">Matrix Synapse Bots</h2>
            <p className="text-sm text-slate-400">
              Webhook-Anbindungen für Health-Alerts und Automations-Rückmeldungen.
            </p>
          </div>
        </div>
        <div className="px-6 py-4">
          {data?.matrixRooms?.length ? (
            <dl className="grid gap-3 text-sm text-slate-300">
              {data.matrixRooms.map((room) => (
                <Fragment key={room.room}>
                  <div className="flex items-center justify-between rounded-lg border border-slate-800 bg-slate-950/60 px-4 py-3">
                    <div>
                      <dt className="text-xs uppercase tracking-widest text-slate-500">
                        {room.bot}
                      </dt>
                      <dd className="text-base font-semibold text-white">{room.room}</dd>
                    </div>
                    <span
                      className={`rounded-full px-3 py-1 text-xs font-semibold uppercase ${
                        room.active
                          ? 'bg-emerald-500/10 text-emerald-300'
                          : 'bg-rose-500/10 text-rose-300'
                      }`}
                    >
                      {room.active ? 'aktiv' : 'inaktiv'}
                    </span>
                  </div>
                </Fragment>
              ))}
            </dl>
          ) : (
            <p className="text-sm text-slate-400">
              Noch keine Bots registriert. Richte Webhooks im Installer ein.
            </p>
          )}
        </div>
      </section>
    </div>
  );
};

export default StatusDashboard;
