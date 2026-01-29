import { DatePin, DatePinStatus } from '@/types/datePin';
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { 
  MapPin, 
  ExternalLink, 
  Clock, 
  Heart, 
  Check, 
  Calendar,
  Trash2,
  Edit
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { formatDistanceToNow, format } from 'date-fns';

interface DatePinDetailProps {
  pin: DatePin | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onUpdateStatus: (id: string, status: DatePinStatus) => void;
  onDelete: (id: string) => void;
}

const typeConfig = {
  restaurant: { label: 'Restaurant', className: 'tag-restaurant' },
  outdoor: { label: 'Outdoor', className: 'tag-outdoor' },
  home: { label: 'At Home', className: 'tag-home' },
  event: { label: 'Event', className: 'tag-event' },
};

const statusOptions: { value: DatePinStatus; label: string; icon: typeof Heart }[] = [
  { value: 'saved', label: 'Saved', icon: Heart },
  { value: 'planned', label: 'Planned', icon: Calendar },
  { value: 'done', label: 'Done', icon: Check },
];

export function DatePinDetail({ 
  pin, 
  open, 
  onOpenChange, 
  onUpdateStatus,
  onDelete 
}: DatePinDetailProps) {
  if (!pin) return null;

  const typeInfo = typeConfig[pin.type];

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full sm:max-w-[450px] bg-card border-l-border/50 overflow-y-auto">
        <SheetHeader className="text-left pb-4 border-b border-border/50">
          <div className="flex items-center gap-2 mb-2">
            <span className={cn("tag-pill", typeInfo.className)}>{typeInfo.label}</span>
          </div>
          <SheetTitle className="font-display text-2xl pr-8">{pin.title}</SheetTitle>
        </SheetHeader>

        <div className="py-6 space-y-6">
          {/* Status Selector */}
          <div className="space-y-2">
            <label className="text-sm font-medium text-muted-foreground">Status</label>
            <div className="flex gap-2">
              {statusOptions.map(option => (
                <Button
                  key={option.value}
                  variant={pin.status === option.value ? 'default' : 'outline'}
                  size="sm"
                  onClick={() => onUpdateStatus(pin.id, option.value)}
                  className={cn(
                    "flex-1",
                    pin.status === option.value && "bg-primary text-primary-foreground"
                  )}
                >
                  <option.icon className="w-4 h-4 mr-1.5" />
                  {option.label}
                </Button>
              ))}
            </div>
          </div>

          {/* Notes */}
          {pin.notes && (
            <div className="space-y-2">
              <label className="text-sm font-medium text-muted-foreground">Notes</label>
              <p className="text-foreground bg-muted/50 rounded-xl p-4 text-sm leading-relaxed">
                {pin.notes}
              </p>
            </div>
          )}

          {/* Location */}
          {pin.location && (
            <div className="space-y-2">
              <label className="text-sm font-medium text-muted-foreground">Location</label>
              <div className="flex items-center gap-2 bg-accent/10 rounded-xl p-4">
                <MapPin className="w-5 h-5 text-accent flex-shrink-0" />
                <span className="text-foreground">{pin.location.name}</span>
              </div>
            </div>
          )}

          {/* Link */}
          {pin.link && (
            <div className="space-y-2">
              <label className="text-sm font-medium text-muted-foreground">Link</label>
              <a
                href={pin.link}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-2 text-primary hover:underline bg-primary/5 rounded-xl p-4 transition-colors hover:bg-primary/10"
              >
                <ExternalLink className="w-4 h-4 flex-shrink-0" />
                <span className="truncate text-sm">{pin.link}</span>
              </a>
            </div>
          )}

          {/* Tags */}
          {pin.tags && pin.tags.length > 0 && (
            <div className="space-y-2">
              <label className="text-sm font-medium text-muted-foreground">Tags</label>
              <div className="flex flex-wrap gap-2">
                {pin.tags.map(tag => (
                  <Badge key={tag} variant="secondary" className="text-sm">
                    #{tag}
                  </Badge>
                ))}
              </div>
            </div>
          )}

          {/* Metadata */}
          <div className="space-y-3 pt-4 border-t border-border/50">
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Clock className="w-4 h-4" />
              <span>Added {format(pin.createdAt, 'MMM d, yyyy')}</span>
              <span className="text-muted-foreground/50">
                ({formatDistanceToNow(pin.createdAt, { addSuffix: true })})
              </span>
            </div>
            {pin.lastViewedAt && (
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <span className="ml-6">Last viewed {formatDistanceToNow(pin.lastViewedAt, { addSuffix: true })}</span>
              </div>
            )}
          </div>

          {/* Actions */}
          <div className="flex gap-3 pt-4">
            <Button variant="outline" className="flex-1" disabled>
              <Edit className="w-4 h-4 mr-2" />
              Edit
            </Button>
            <Button 
              variant="outline" 
              className="text-destructive hover:text-destructive hover:bg-destructive/10"
              onClick={() => {
                onDelete(pin.id);
                onOpenChange(false);
              }}
            >
              <Trash2 className="w-4 h-4" />
            </Button>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}
