import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "@/auth/AuthContext";

export default function Login() {
  const { signInWithGoogle, signIn, loading } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");

  async function handleGoogle() {
    try {
      await signInWithGoogle();
      navigate("/app");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Google sign-in failed");
    }
  }

  async function handleEmail(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    try {
      await signIn(email, password);
      navigate("/app");
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Sign in failed");
    }
  }

  if (loading) return null;

  return (
    <div className="page-center">
      <div className="anim w-full max-w-[360px] text-center">
        <div className="logo-icon">🧭</div>
        <h1 className="font-display italic text-4xl text-roam-text leading-none mb-2">roam</h1>
        <p className="font-mono text-[10px] text-roam-text-muted tracking-[1.5px] uppercase mb-8">plan your adventures</p>

        <button onClick={handleGoogle} className="anim d1 w-full py-3.5 px-5 bg-roam-surface border border-roam-logan/25 rounded-[13px] font-mono text-[13px] text-roam-text cursor-pointer flex items-center justify-center gap-2.5 shadow-card mb-4">
          <svg width="18" height="18" viewBox="0 0 24 24"><path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 01-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/><path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/><path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/><path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/></svg>
          continue with google
        </button>

        <div className="flex items-center gap-3 my-4">
          <div className="flex-1 h-px bg-roam-logan/20" />
          <span className="font-mono text-[9px] text-roam-text-muted tracking-[1px]">or</span>
          <div className="flex-1 h-px bg-roam-logan/20" />
        </div>

        <form onSubmit={handleEmail} className="anim d2">
          <input value={email} onChange={(e) => setEmail(e.target.value)} type="email" placeholder="email" className="input-field mb-2" />
          <input value={password} onChange={(e) => setPassword(e.target.value)} type="password" placeholder="password" className="input-field mb-4" />
          <button type="submit" className="btn-primary-lg">
            sign in
          </button>
        </form>

        {error && <p className="font-mono text-[11px] text-roam-error mt-3">{error}</p>}

        <p className="anim d3 font-mono text-[10px] text-roam-text-muted mt-5">
          don't have an account? <a href="/signup" className="text-roam-logan-deep underline">sign up</a>
        </p>
      </div>
    </div>
  );
}
