interface EmptyStateProps {
  icon: string;
  title: string;
  subtitle: string;
}

export function EmptyState({ icon, title, subtitle }: EmptyStateProps) {
  return (
    <div className="anim text-center py-20">
      <div className="empty-icon">{icon}</div>
      <p className="font-display italic text-xl text-roam-text mb-2">{title}</p>
      <p className="font-notes text-[13px] text-roam-text-muted m-0">{subtitle}</p>
    </div>
  );
}
