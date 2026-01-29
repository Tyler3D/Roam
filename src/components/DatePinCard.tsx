import { DatePin } from '@/types/datePin';
import { MapPin, ExternalLink, Clock, Heart, Check, Calendar } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';
import { formatDistanceToNow } from 'date-fns';

interface DatePinCardProps {
  pin: DatePin;
  variant?: 'default' | 'compact' | 'featured';
  onClick?: () => void;
}

const typeConfig = {
  restaurant: { label: 'Restaurant', className: 'tag-restaurant' },
  outdoor: { label: 'Outdoor', className: 'tag-outdoor' },
  home: { label: 'At Home', className: 'tag-home' },
  event: { label: 'Event', className: 'tag-event' },
};

const statusConfig = {
  saved: { icon: Heart, label: 'Saved', className: 'text-primary' },
  planned: { icon: Calendar, label: 'Planned', className: 'text-highlight' },
  done: { icon: Check, label: 'Done', className: 'text-accent' },
};

export function DatePinCard({ pin, variant = 'default', onClick }: DatePinCardProps) {
  const typeInfo = typeConfig[pin.type];
  const statusInfo = statusConfig[pin.status];
  const StatusIcon = statusInfo.icon;

  if (variant === 'compact') {
    return (
      <div
        onClick={onClick}
        className={cn(
          "glass-card rounded-xl p-4 cursor-pointer transition-all duration-300",
          "hover:shadow-elevated hover:scale-[1.02] hover:border-primary/30",
          "animate-fade-in"
        )}
      >
        <div className="flex items-start justify-between gap-3">
          <div className="flex-1 min-w-0">
            <h3 className="font-display font-medium text-foreground truncate">{pin.title}</h3>
            {pin.location && (
              <p className="text-sm text-muted-foreground flex items-center gap-1 mt-1">
                <MapPin className="w-3 h-3" />
                <span className="truncate">{pin.location.name}</span>
              </p>
            )}
          </div>
          <span className={cn("tag-pill", typeInfo.className)}>{typeInfo.label}</span>
        </div>
      </div>
    );
  }

  if (variant === 'featured') {
    return (
      <div
        onClick={onClick}
        className={cn(
          "glow-card rounded-2xl p-5 cursor-pointer transition-all duration-300",
          "hover:shadow-glow hover:scale-[1.01]",
          "animate-scale-in min-w-[280px] max-w-[320px] flex-shrink-0"
        )}
      >
        <div className="flex items-start justify-between mb-3">
          <span className={cn("tag-pill", typeInfo.className)}>{typeInfo.label}</span>
          <StatusIcon className={cn("w-4 h-4", statusInfo.className)} />
        </div>
        
        <h3 className="font-display text-lg font-semibold text-foreground mb-2 line-clamp-2">
          {pin.title}
        </h3>
        
        {pin.notes && (
          <p className="text-sm text-muted-foreground line-clamp-2 mb-3">
            {pin.notes}
          </p>
        )}
        
        <div className="flex items-center justify-between text-xs text-muted-foreground">
          {pin.location ? (
            <span className="flex items-center gap-1">
              <MapPin className="w-3 h-3 text-accent" />
              <span className="truncate max-w-[120px]">{pin.location.name}</span>
            </span>
          ) : (
            <span></span>
          )}
          <span className="flex items-center gap-1">
            <Clock className="w-3 h-3" />
            {formatDistanceToNow(pin.createdAt, { addSuffix: true })}
          </span>
        </div>
      </div>
    );
  }

  // Default variant
  return (
    <div
      onClick={onClick}
      className={cn(
        "elevated-card rounded-2xl p-5 cursor-pointer transition-all duration-300",
        "hover:shadow-elevated hover:scale-[1.01] hover:border-primary/20",
        "animate-fade-in"
      )}
    >
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-2">
          <span className={cn("tag-pill", typeInfo.className)}>{typeInfo.label}</span>
          {pin.status !== 'saved' && (
            <Badge variant="outline" className="text-xs">
              <StatusIcon className={cn("w-3 h-3 mr-1", statusInfo.className)} />
              {statusInfo.label}
            </Badge>
          )}
        </div>
        {pin.link && (
          <ExternalLink className="w-4 h-4 text-muted-foreground hover:text-primary transition-colors" />
        )}
      </div>

      <h3 className="font-display text-xl font-semibold text-foreground mb-2">
        {pin.title}
      </h3>

      {pin.notes && (
        <p className="text-sm text-muted-foreground line-clamp-2 mb-4">
          {pin.notes}
        </p>
      )}

      {pin.tags && pin.tags.length > 0 && (
        <div className="flex flex-wrap gap-1 mb-4">
          {pin.tags.slice(0, 3).map(tag => (
            <span key={tag} className="text-xs text-muted-foreground bg-muted px-2 py-0.5 rounded-full">
              #{tag}
            </span>
          ))}
        </div>
      )}

      <div className="flex items-center justify-between text-xs text-muted-foreground pt-3 border-t border-border/50">
        {pin.location ? (
          <span className="flex items-center gap-1">
            <MapPin className="w-3 h-3 text-accent" />
            {pin.location.name}
          </span>
        ) : (
          <span className="text-muted-foreground/50">No location</span>
        )}
        <span className="flex items-center gap-1">
          <Clock className="w-3 h-3" />
          {formatDistanceToNow(pin.createdAt, { addSuffix: true })}
        </span>
      </div>
    </div>
  );
}
