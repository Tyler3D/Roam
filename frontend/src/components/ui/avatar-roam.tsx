import { cn } from "@/lib/utils";

interface AvatarProps {
  name: string;
  size?: number;
  src?: string | null;
  className?: string;
}

export function Avatar({ name, size = 22, src, className }: AvatarProps) {
  const fontSize = Math.max(8, Math.round(size * 0.45));
  return (
    <div className={cn("avatar-circle", className)} style={{ width: size, height: size }}>
      {src ? (
        <img src={src} alt="" className="rounded-full" style={{ width: size, height: size }} referrerPolicy="no-referrer" />
      ) : (
        <span className="font-mono text-white font-semibold" style={{ fontSize }}>
          {(name || "?")[0].toUpperCase()}
        </span>
      )}
    </div>
  );
}
