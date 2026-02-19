import { HashRouter, Routes, Route } from "react-router-dom";
import Hub from "./components/Hub";
import Settings from "./components/Settings";
import FloatingBar from "./components/FloatingBar";
import Onboarding from "./components/Onboarding";

function App() {
  return (
    <HashRouter>
      <Routes>
        <Route path="/" element={<Hub />} />
        <Route path="/settings" element={<Settings />} />
        <Route path="/floating" element={<FloatingBar />} />
        <Route path="/onboarding" element={<Onboarding />} />
      </Routes>
    </HashRouter>
  );
}

export default App;
