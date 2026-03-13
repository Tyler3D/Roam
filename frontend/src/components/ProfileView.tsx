import { useDeferredValue, useState } from "react";
import { useAuth } from "@/auth/AuthContext";
import { useMe, useSearchUsers } from "@/api/users";
import { useFriends, useFriendRequests, useAcceptFriendRequest, useSendFriendRequest } from "@/api/friends";
import { Avatar } from "@/components/ui/avatar-roam";
import { Spinner } from "@/components/ui/spinner";
import type { Friendship } from "@/models/friendship";
import type { User } from "@/models/user";

export default function ProfileView() {
  const { user, signOutUser } = useAuth();
  const { data: profile } = useMe();
  const { data: friends = [] } = useFriends();
  const { data: requests = [] } = useFriendRequests();
  const acceptRequest = useAcceptFriendRequest();
  const sendRequest = useSendFriendRequest();

  const [searchInput, setSearchInput] = useState("");
  const deferredQuery = useDeferredValue(searchInput.trim());
  const { data: searchResults = [], isFetching } = useSearchUsers(deferredQuery);

  const friendIds = new Set(friends.map((f) => f.friendId).filter(Boolean) as string[]);
  const filteredResults = searchResults.filter(
    (u) => !friendIds.has(u.id) && u.id !== profile?.id
  );

  function handleSendRequest(userId: string) {
    sendRequest.mutate(userId);
  }

  const initials = profile
    ? `${profile.firstName[0] ?? ""}${profile.lastName[0] ?? ""}`.toUpperCase() || "?"
    : "?";

  return (
    <div>
      <div className="anim text-center mb-8">
        <Avatar name={initials} size={64} src={user?.photoURL} className="mx-auto mb-3" />
        <p className="font-display text-[22px] text-roam-text mb-1">{profile?.firstName} {profile?.lastName}</p>
        {profile?.username && <p className="font-mono text-[11px] text-roam-text-muted m-0">@{profile.username}</p>}
      </div>

      {requests.length > 0 && (
        <div className="anim d1 mb-6">
          <p className="label-mono mb-2.5">friend requests</p>
          {requests.map((r: Friendship) => (
            <div key={r.id} className="flex items-center justify-between py-2.5 px-3.5 bg-roam-surface rounded-xl border border-roam-logan/20 mb-1.5">
              <span className="font-mono text-xs text-roam-text">{r.friendFirstName} {r.friendLastName}</span>
              <button onClick={() => acceptRequest.mutate(r.id)} className="btn-primary py-1.5 px-3 rounded-lg shadow-none">accept</button>
            </div>
          ))}
        </div>
      )}

      <div className="anim d2 mb-6">
        <p className="label-mono mb-2.5">friends ({friends.length})</p>
        {friends.length === 0 ? (
          <p className="font-notes text-[13px] text-roam-text-muted">no friends yet — search to add people</p>
        ) : (
          <div className="flex flex-wrap gap-2">
            {friends.map((f: Friendship) => (
              <div key={f.id} className="member-chip bg-roam-lavender/50 border border-roam-logan/20">
                <Avatar name={f.friendFirstName ?? "?"} size={22} src={f.friendPhotoUrl} />
                <span className="font-mono text-[10px] text-roam-text-mid">{f.friendFirstName} {f.friendLastName}</span>
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="anim d3 mb-6">
        <p className="label-mono mb-2.5">add friends</p>
        <input
          value={searchInput}
          onChange={(e) => setSearchInput(e.target.value)}
          placeholder="search by name or username..."
          className="input-field w-full text-xs py-2.5 px-3.5 rounded-[11px] mb-2.5"
        />
        {deferredQuery.length >= 2 && (
          <div className="space-y-1.5">
            {isFetching ? (
              <div className="py-4 flex justify-center">
                <Spinner />
              </div>
            ) : filteredResults.length === 0 ? (
              <p className="py-4 font-notes text-[13px] text-roam-text-muted text-center">
                no users found
              </p>
            ) : (
              filteredResults.map((u: User) => (
                <div key={u.id} className="flex items-center justify-between py-2.5 px-3.5 bg-roam-surface rounded-xl border border-roam-logan/20">
                  <div className="flex items-center gap-2.5 min-w-0">
                    <Avatar name={u.firstName} size={28} src={u.photoUrl} />
                    <div className="min-w-0">
                      <p className="font-mono text-xs text-roam-text m-0">
                        {u.firstName} {u.lastName}
                      </p>
                      {u.username && (
                        <p className="font-mono text-[10px] text-roam-text-muted m-0">
                          @{u.username}
                        </p>
                      )}
                    </div>
                  </div>
                  <button
                    onClick={() => handleSendRequest(u.id)}
                    className="font-mono text-[9px] tracking-[1.5px] uppercase bg-roam-lavender text-roam-logan-deep border-none rounded-lg py-1.5 px-3 cursor-pointer shrink-0"
                  >
                    add friend
                  </button>
                </div>
              ))
            )}
          </div>
        )}
      </div>

      <div className="anim d4 text-center">
        <button onClick={() => signOutUser()} className="font-mono text-[11px] text-roam-text-muted bg-transparent border-none cursor-pointer py-3 px-5">sign out</button>
      </div>
    </div>
  );
}
