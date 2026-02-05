import { DatePin } from '@/types/datePin';
import { Badge } from '@/components/ui/badge';
import { X, ExternalLink, MapPin, Calendar } from 'lucide-react';
import { cn } from '@/lib/utils';
import { format } from 'date-fns';

interface MapPinPopupProps {
  pin: DatePin;
  onClose: () => void;
  onViewDetails: () => void;
}

const typeLabels = {
  restaurant: 'Restaurant',
  outdoor: 'Outdoor',
  home: 'At Home',
  event: 'Event',
};

const statusColors = {
  saved: 'bg-primary/10 text-primary',
  planned: 'bg-accent/10 text-accent-foreground',
  done: 'bg-muted text-muted-foreground',
};

export function MapPinPopup({ pin, onClose, onViewDetails }: MapPinPopupProps) {
  return (
    <div className="bg-card rounded-xl shadow-lg border border-border/50 w-64 overflow-hidden animate-fade-in">
      {/* Header */}
      <div className="flex items-start justify-between p-3 pb-2">
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-foreground truncate text-sm">
            {pin.title}
          </h3>
          <div className="flex items-center gap-1.5 mt-0.5">
            <Badge variant="outline" className="text-xs px-1.5 py-0">
              {typeLabels[pin.type]}
            </Badge>
            <span className={cn("text-xs px-1.5 py-0 rounded-full", statusColors[pin.status])}>
              {pin.status}
            </span>
          </div>
        </div>
        <button
          onClick={(e) => {
            e.stopPropagation();
            onClose();
          }}
          className="p-1 rounded-full hover:bg-muted transition-colors -mr-1 -mt-1"
        >
          <X className="w-3.5 h-3.5 text-muted-foreground" />
        </button>
      </div>

      {/* Content */}
      <div className="px-3 pb-2">
        {pin.location && (
          <div className="flex items-center gap-1.5 text-xs text-muted-foreground mb-1.5">
            <MapPin className="w-3 h-3 shrink-0" />
            <span className="truncate">{pin.location.name}</span>
          </div>
        )}
        
        {pin.notes && (
          <p className="text-xs text-muted-foreground line-clamp-2 mb-1.5">
            {pin.notes}
          </p>
        )}

        <div className="flex items-center gap-1.5 text-xs text-muted-foreground/70">
          <Calendar className="w-3 h-3" />
          <span>{format(new Date(pin.createdAt), 'MMM d, yyyy')}</span>
        </div>
      </div>

      {/* Tags */}
      {pin.tags && pin.tags.length > 0 && (
        <div className="px-3 pb-2">
          <div className="flex flex-wrap gap-1">
            {pin.tags.slice(0, 3).map(tag => (
              <span
                key={tag}
                className="text-xs bg-primary/10 text-primary px-1.5 py-0.5 rounded-full"
              >
                #{tag}
              </span>
            ))}
            {pin.tags.length > 3 && (
              <span className="text-xs text-muted-foreground">
                +{pin.tags.length - 3}
              </span>
            )}
          </div>
        </div>
      )}

      {/* Actions */}
      <div className="border-t border-border/50 p-2 flex gap-2">
        <button
          onClick={(e) => {
            e.stopPropagation();
            onViewDetails();
          }}
          className="flex-1 text-xs font-medium text-primary hover:bg-primary/10 rounded-lg py-1.5 px-2 transition-colors"
        >
          View Details
        </button>
        {pin.link && (
          <a
            href={pin.link}
            target="_blank"
            rel="noopener noreferrer"
            onClick={(e) => e.stopPropagation()}
            className="flex items-center gap-1 text-xs font-medium text-muted-foreground hover:bg-muted rounded-lg py-1.5 px-2 transition-colors"
          >
            <ExternalLink className="w-3 h-3" />
          </a>
        )}
      </div>
    </div>
  );
}
