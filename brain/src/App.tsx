import { useEffect, useState } from 'react';
import { HashRouter, Routes, Route } from 'react-router-dom';
import { initDB } from './lib/store';
import { useSettings } from './lib/hooks';
import Layout from './components/Layout';
import Onboarding from './pages/Onboarding';
import BrainHub from './pages/BrainHub';
import Positioning from './pages/Positioning';
import Ideas from './pages/Ideas';
import Writing from './pages/Writing';
import Production from './pages/Production';
import Publishing from './pages/Publishing';
import Analysis from './pages/Analysis';
import Monetization from './pages/Monetization';
import Progression from './pages/Progression';
import SettingsPage from './pages/Settings';

function Shell() {
  const settings = useSettings();
  const [skipOnboarding, setSkipOnboarding] = useState(false);

  if (!settings.onboardingDone && !skipOnboarding) {
    return <Onboarding onDone={() => setSkipOnboarding(true)} />;
  }

  return (
    <Routes>
      <Route path="/" element={<BrainHub />} />
      <Route element={<Layout />}>
        <Route path="/positionnement" element={<Positioning />} />
        <Route path="/idees" element={<Ideas />} />
        <Route path="/ecriture" element={<Writing />} />
        <Route path="/production" element={<Production />} />
        <Route path="/publication" element={<Publishing />} />
        <Route path="/analyse" element={<Analysis />} />
        <Route path="/monetisation" element={<Monetization />} />
        <Route path="/progression" element={<Progression />} />
        <Route path="/reglages" element={<SettingsPage />} />
        <Route path="*" element={<BrainHub />} />
      </Route>
    </Routes>
  );
}

export default function App() {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    initDB().then(() => setReady(true));
  }, []);

  if (!ready) {
    return (
      <div className="flex min-h-screen items-center justify-center text-slate-500">
        <div className="animate-pulse text-2xl">🧠 Chargement…</div>
      </div>
    );
  }

  return (
    <HashRouter>
      <Shell />
    </HashRouter>
  );
}
