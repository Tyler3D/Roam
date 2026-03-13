import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";

console.log("[roam] App boot", window.location.href);
createRoot(document.getElementById("root")!).render(<App />);
