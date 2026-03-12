import { useState } from "react";
import { useAuth } from "@/auth/AuthContext";
import { Avatar } from "@/components/ui/avatar-roam";

interface Props {
  userName?: string | null;
  userImage?: string | null;
  notificationCount?: number;
  onNotificationClick?: () => void;
}

export default function TopBar({ userName, userImage, notificationCount = 0, onNotificationClick }: Props) {
  const { signOutUser } = useAuth();
  const [menuOpen, setMenuOpen] = useState(false);

  const now = new Date();
  const days = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
  const months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
  const dateStr = `${days[now.getDay()]} · ${months[now.getMonth()]} ${String(now.getDate()).padStart(2, "0")}`;

  return (
    <header className="h-14 flex items-center justify-between border-b border-roam-logan/[0.15] bg-roam-bg/85 backdrop-blur-xl shrink-0 sticky top-0 z-50 px-4">
      <div className="flex items-center gap-[7px] min-w-[80px]">
        <span className="font-display italic text-[30px] leading-none text-roam-text">roam</span>
        <span className="font-mono text-[10px] tracking-[1.5px] uppercase bg-roam-lavender text-roam-logan-deep px-1.5 py-0.5 rounded-full">beta</span>
      </div>

      <span className="font-mono text-[13px] text-roam-logan tracking-[0.5px] absolute left-1/2 -translate-x-1/2">{dateStr}</span>

      <div className="flex items-center gap-2.5 min-w-[80px] justify-end">
        <button onClick={onNotificationClick} className={`relative bg-transparent border-none cursor-pointer p-1 flex items-center ${notificationCount > 0 ? "text-roam-logan-deep" : "text-roam-logan"}`}>
          <svg viewBox="0 0 20 20" fill="currentColor" className="w-[18px] h-[18px]">
            <path d="M10 2a6 6 0 00-6 6v3.586l-.707.707A1 1 0 004 14h12a1 1 0 00.707-1.707L16 11.586V8a6 6 0 00-6-6zm0 16a2 2 0 01-2-2h4a2 2 0 01-2 2z" />
          </svg>
          {notificationCount > 0 && (
            <span className="absolute top-[1px] right-[1px] w-2 h-2 rounded-full bg-roam-notif-dot border-[1.5px] border-roam-bg/90" />
          )}
        </button>

        <div className="relative">
          <button onClick={() => setMenuOpen(!menuOpen)} className="flex items-center bg-transparent border-none cursor-pointer p-0">
            <Avatar name={userName || "?"} size={28} src={userImage} />
          </button>

          {menuOpen && (
            <>
              <div className="fixed inset-0 z-10" onClick={() => setMenuOpen(false)} />
              <div className="absolute right-0 top-full mt-2 z-20 w-40 bg-roam-surface border border-roam-logan/20 rounded-[14px] shadow-menu overflow-hidden backdrop-blur-xl">
                <div className="px-3.5 pt-2.5 pb-2 border-b border-roam-logan/10">
                  <p className="font-mono text-[11px] text-roam-text overflow-hidden text-ellipsis whitespace-nowrap m-0">{userName}</p>
                </div>
                <button
                  onClick={() => signOutUser()}
                  className="w-full py-2.5 px-3.5 font-mono text-[11px] text-roam-text-muted text-left bg-transparent border-none cursor-pointer hover:text-roam-text hover:bg-roam-logan/[0.08]"
                >
                  sign out
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </header>
  );
}
