import { useDeferredValue } from "react";
import { useCheckUsername } from "@/api/users";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

interface UsernameInputProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  id?: string;
  className?: string;
  disabled?: boolean;
  required?: boolean;
}

export function UsernameInput({
  value,
  onChange,
  placeholder = "yourname",
  id = "username",
  className,
  disabled,
  required,
}: UsernameInputProps) {
  const deferredUsername = useDeferredValue(value.trim());
  const { data, isFetching, isPending } = useCheckUsername(deferredUsername);

  const showCheck = deferredUsername.length >= 1 && value.trim() === deferredUsername;
  const available = showCheck && !isFetching && !isPending && data && data.available === true;
  const taken = showCheck && !isFetching && !isPending && data && data.available === false;

  const base = value.trim().replace(/^@/, "") || "username";
  const suggestions = taken ? [`${base}_2`, `${base}_nyc`] : [];

  return (
    <div className="space-y-1.5">
      <div className="relative">
        <Input
          id={id}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          disabled={disabled}
          required={required}
          className={cn(
            "pr-10",
            taken && "border-destructive focus-visible:ring-destructive",
            available && "border-green-500/60 focus-visible:ring-green-500/40",
            className
          )}
          autoComplete="username"
        />
        {showCheck && (
          <div className="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none">
            {isFetching || isPending ? (
              <span className="text-muted-foreground text-xs">…</span>
            ) : available ? (
              <span className="text-green-600 text-sm" aria-label="available">✓</span>
            ) : taken ? (
              <span className="text-destructive text-sm" aria-label="taken">✕</span>
            ) : null}
          </div>
        )}
      </div>
      {taken && suggestions.length > 0 && (
        <p className="text-xs text-muted-foreground">
          Try <span className="font-mono">{suggestions.join(" or ")}</span>
        </p>
      )}
    </div>
  );
}
