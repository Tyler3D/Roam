import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useUpdateMe } from "@/api/users";

export default function Onboarding() {
  const navigate = useNavigate();
  const updateMe = useUpdateMe();
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [phone, setPhone] = useState("");

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!firstName.trim()) return;
    updateMe.mutate(
      {
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        phone: phone.trim() || undefined,
        isOnboarded: true,
      },
      { onSuccess: () => navigate("/app") },
    );
  }

  return (
    <div className="page-center">
      <div className="anim w-full max-w-[360px] text-center">
        <div className="logo-icon">👋</div>
        <h1 className="font-display italic text-[28px] text-roam-text leading-none mb-2">welcome to roam</h1>
        <p className="font-mono text-[10px] text-roam-text-muted tracking-[1.5px] uppercase mb-8">tell us a bit about yourself</p>

        <form onSubmit={handleSubmit}>
          <div className="flex gap-2 mb-2">
            <input value={firstName} onChange={(e) => setFirstName(e.target.value)} placeholder="first name" required className="input-field flex-1" />
            <input value={lastName} onChange={(e) => setLastName(e.target.value)} placeholder="last name" className="input-field flex-1" />
          </div>

          <input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="phone (optional)" type="tel" className="input-field mb-4" />

          <button type="submit" disabled={updateMe.isPending} className="btn-primary-lg" style={{ opacity: updateMe.isPending ? 0.7 : 1 }}>
            {updateMe.isPending ? "saving..." : "get started →"}
          </button>
        </form>
      </div>
    </div>
  );
}
