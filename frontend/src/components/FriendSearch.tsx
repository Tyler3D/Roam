import { useDeferredValue, useState } from "react";
import { useSearchUsers } from "@/api/users";
import { Avatar } from "@/components/ui/avatar-roam";
import { Spinner } from "@/components/ui/spinner";
import { cn } from "@/lib/utils";
import type { User } from "@/models/user";

interface FriendSearchProps {
  onSelect: (user: User) => void;
  excludeIds?: string[];
  placeholder?: string;
  className?: string;
}

export function FriendSearch({
  onSelect,
  excludeIds = [],
  placeholder = "search by name or username...",
  className,
}: FriendSearchProps) {
  const [query, setQuery] = useState("");
  const deferredQuery = useDeferredValue(query);
  const { data: results = [], isFetching } = useSearchUsers(deferredQuery);

  const filtered = results.filter((u) => !excludeIds.includes(u.id));
  const showDropdown = deferredQuery.length >= 2;
  const isEmpty = showDropdown && !isFetching && filtered.length === 0;

  function handleSelect(u: User) {
    onSelect(u);
    setQuery("");
  }

  return (
    <div className={cn("relative", className)}>
      <input
        type="text"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder={placeholder}
        className="input-field w-full text-xs py-2.5 px-3.5 rounded-[11px]"
      />
      {showDropdown && (
        <div className="absolute top-full left-0 right-0 mt-1.5 bg-white/[0.98] border border-roam-logan/30 rounded-xl shadow-dropdown overflow-hidden z-50 max-h-[220px] overflow-y-auto">
          {isFetching ? (
            <div className="py-4 flex justify-center">
              <Spinner />
            </div>
          ) : isEmpty ? (
            <p className="py-4 px-3.5 font-notes text-[13px] text-roam-text-muted text-center">
              no users found
            </p>
          ) : (
            filtered.map((u) => (
              <button
                key={u.id}
                type="button"
                onMouseDown={(e) => {
                  e.preventDefault();
                  handleSelect(u);
                }}
                className="flex items-center gap-2.5 w-full py-2.5 px-3.5 bg-transparent border-none cursor-pointer text-left hover:bg-roam-lavender/40"
              >
                <Avatar name={u.firstName} size={28} src={u.photoUrl} />
                <div className="min-w-0 flex-1">
                  <span className="font-mono text-xs text-roam-text">
                    {u.firstName} {u.lastName}
                  </span>
                  {u.username && (
                    <span className="font-mono text-[10px] text-roam-text-muted ml-1.5">
                      @{u.username}
                    </span>
                  )}
                </div>
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
}
