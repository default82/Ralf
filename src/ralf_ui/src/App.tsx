import StatusDashboard from './components/StatusDashboard';

const App = () => (
  <div className="min-h-screen bg-slate-950 text-slate-100">
    <header className="border-b border-slate-800 bg-slate-900/80 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <div>
          <p className="text-xs uppercase tracking-[0.3em] text-slate-400">R.A.L.F.</p>
          <h1 className="text-2xl font-semibold text-white">Status & Health Overview</h1>
        </div>
        <span className="rounded-full border border-brand/60 px-4 py-1 text-xs font-semibold uppercase tracking-wider text-brand">
          Tech Preview
        </span>
      </div>
    </header>
    <main className="mx-auto max-w-6xl px-6 py-8">
      <StatusDashboard />
    </main>
  </div>
);

export default App;
