interface LocationLinkProps {
  placeName: string;
}

export function LocationLink({ placeName }: LocationLinkProps) {
  return (
    <a
      href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(placeName)}`}
      target="_blank"
      rel="noopener noreferrer"
      className="inline-flex items-center gap-1.5 font-mono text-[11px] text-roam-logan-deep no-underline"
    >
      <span>📍</span>
      <span className="underline decoration-roam-logan-deep/30">{placeName}</span>
      <span className="text-roam-logan">↗</span>
    </a>
  );
}
