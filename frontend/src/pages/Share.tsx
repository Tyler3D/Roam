import { useEffect } from "react";
import { useParams, useNavigate } from "react-router-dom";

export default function Share() {
  const { shareCode } = useParams<{ shareCode: string }>();
  const navigate = useNavigate();

  useEffect(() => {
    if (shareCode) {
      navigate(`/share/schedule?uid=${shareCode}`, { replace: true });
    }
  }, [shareCode, navigate]);

  return (
    <div className="dot-grid" style={{ minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center", background: "#F5F3FA" }}>
      <span style={{ fontFamily: "'DM Mono', monospace", fontSize: 11, color: "#A89FC0" }}>redirecting...</span>
    </div>
  );
}
