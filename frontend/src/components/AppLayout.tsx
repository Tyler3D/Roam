import { Outlet, useLocation, useNavigate } from "react-router-dom";
import { useUnreadCount } from "@/api/notifications";
import { useMe } from "@/api/users";
import { usePlansDrafts } from "@/api/plans";
import TopBar from "./TopBar";

const TABS = [
  { id: "ideas", symbol: "◌", label: "ideas", path: "/app" },
  { id: "drafts", symbol: "⊟", label: "drafts", path: "/app/drafts" },
  { id: "plans", symbol: "⊕", label: "plans", path: "/app/plans" },
  { id: "map", symbol: "◎", label: "map", path: "/app/map" },
] as const;

export default function AppLayout() {
  const location = useLocation();
  const navigate = useNavigate();
  const { data: profile } = useMe();
  const { data: drafts = [] } = usePlansDrafts();
  const unreadCount = useUnreadCount();

  const draftsCount = drafts.length;
  const activePath = location.pathname;

  return (
    <div className="dot-grid h-dvh flex flex-col bg-roam-bg">
      <TopBar
        userName={profile?.firstName ? `${profile.firstName} ${profile.lastName}` : undefined}
        userPhotoUrl={profile?.photoUrl}
        userFirstName={profile?.firstName}
        userLastName={profile?.lastName}
        userCity={profile?.city}
        notificationCount={unreadCount}
        onNotificationClick={() => navigate("/app/notifications")}
      />

      <main className="flex-1 overflow-y-auto" style={{ paddingBottom: 72 }}>
        <Outlet />
      </main>

      <nav className="glass-bar bottom-0 h-[60px] border-t flex items-stretch z-50" style={{ background: "rgba(245,243,250,0.95)" }}>
        {TABS.map((tab) => {
          const isActive =
            activePath === tab.path ||
            (tab.id === "ideas" && (activePath === "/app" || activePath === "/app/"));
          return (
            <button
              key={tab.id}
              onClick={() => navigate(tab.path)}
              className="flex-1 flex flex-col items-center justify-center gap-[3px] bg-transparent border-none cursor-pointer relative"
            >
              {isActive && <div className="absolute top-1.5 w-1 h-1 rounded-full bg-roam-logan-deep" />}
              <span className={`font-mono text-[22px] leading-none ${isActive ? "text-roam-logan-deep" : "text-roam-logan"}`}>
                {tab.symbol}
              </span>
              <span className={`font-mono text-[11px] tracking-[1px] uppercase ${isActive ? "text-roam-logan-deep" : "text-roam-lav-deep"}`}>
                {tab.label}
              </span>
              {tab.id === "drafts" && draftsCount > 0 && (
                <span className="absolute top-1.5 right-[calc(50%-14px)] min-w-[14px] h-[14px] px-1 flex items-center justify-center rounded-full bg-roam-logan-deep text-white font-mono text-[9px]">
                  {draftsCount > 99 ? "99+" : draftsCount}
                </span>
              )}
            </button>
          );
        })}
      </nav>
    </div>
  );
}
