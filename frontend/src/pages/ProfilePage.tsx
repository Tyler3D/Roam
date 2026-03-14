import { useNavigate } from "react-router-dom";
import ProfileView from "@/components/ProfileView";

export default function ProfilePage() {
  const navigate = useNavigate();

  return (
    <div className="min-h-dvh bg-roam-bg">
      <header className="h-14 flex items-center border-b border-roam-logan/[0.15] bg-roam-bg/85 backdrop-blur-xl sticky top-0 z-50 px-4">
        <button
          onClick={() => navigate("/app")}
          className="font-mono text-[11px] text-roam-logan-deep bg-transparent border-none cursor-pointer"
        >
          ← back
        </button>
      </header>
      <div className="max-w-[480px] mx-auto pt-5 px-4 pb-24">
        <ProfileView />
      </div>
    </div>
  );
}
