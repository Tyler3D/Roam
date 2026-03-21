import { useState, useCallback } from 'react';
import { DatePinFormData, DatePinType } from '@/types/datePin';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import {
  UtensilsCrossed,
  Trees,
  Home,
  CalendarDays,
  Link,
  Tag,
  Coffee,
  Beer,
  Sparkles,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { LocationAutocomplete } from '@/components/LocationAutocomplete';

interface AddDatePinDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (data: DatePinFormData) => void;
}

const typeOptions: { value: DatePinType; label: string; icon: typeof UtensilsCrossed }[] = [
  { value: 'restaurant', label: 'Restaurant', icon: UtensilsCrossed },
  { value: 'cafe', label: 'Café', icon: Coffee },
  { value: 'bar', label: 'Bar', icon: Beer },
  { value: 'nightlife', label: 'Nightlife', icon: Sparkles },
  { value: 'outdoor', label: 'Outdoor', icon: Trees },
  { value: 'home', label: 'At Home', icon: Home },
  { value: 'event', label: 'Event', icon: CalendarDays },
];

interface LocationData {
  name: string;
  lat: number;
  lng: number;
}

export function AddDatePinDialog({ open, onOpenChange, onSave }: AddDatePinDialogProps) {
  const [formData, setFormData] = useState<DatePinFormData>({
    title: '',
    notes: '',
    link: '',
    locationName: '',
    type: 'restaurant',
    tags: [],
  });
  const [location, setLocation] = useState<LocationData | null>(null);
  const [tagInput, setTagInput] = useState('');
  const [locationError, setLocationError] = useState(false);

  const handleLocationChange = useCallback((loc: LocationData | null) => {
    setLocation(loc);
    setFormData(prev => ({ ...prev, locationName: loc?.name || '' }));
    if (loc) {
      setLocationError(false);
    }
  }, []);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!formData.title.trim()) return;
    
    // Validate location is set
    if (!location) {
      setLocationError(true);
      return;
    }

    // Include full location data
    const dataToSave: DatePinFormData = {
      ...formData,
      locationName: location.name,
      locationLat: location.lat,
      locationLng: location.lng,
    };

    onSave(dataToSave);
    
    // Reset form
    setFormData({
      title: '',
      notes: '',
      link: '',
      locationName: '',
      type: 'restaurant',
      tags: [],
    });
    setLocation(null);
    setTagInput('');
    setLocationError(false);
    onOpenChange(false);
  };

  const handleAddTag = () => {
    if (tagInput.trim() && !formData.tags?.includes(tagInput.trim())) {
      setFormData(prev => ({
        ...prev,
        tags: [...(prev.tags || []), tagInput.trim()],
      }));
      setTagInput('');
    }
  };

  const handleRemoveTag = (tag: string) => {
    setFormData(prev => ({
      ...prev,
      tags: prev.tags?.filter(t => t !== tag),
    }));
  };

  const handleClose = () => {
    setFormData({
      title: '',
      notes: '',
      link: '',
      locationName: '',
      type: 'restaurant',
      tags: [],
    });
    setLocation(null);
    setTagInput('');
    setLocationError(false);
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="sm:max-w-[500px] bg-card border-border/50">
        <DialogHeader>
          <DialogTitle className="font-display text-2xl">Save a Date Idea</DialogTitle>
          <DialogDescription>
            Add a new date idea with a location to see it on the map.
          </DialogDescription>
        </DialogHeader>
        
        <form onSubmit={handleSubmit} className="space-y-5 mt-4">
          <div className="space-y-2">
            <Label htmlFor="title">What's the idea? *</Label>
            <Input
              id="title"
              placeholder="e.g., Rooftop bar at sunset"
              value={formData.title}
              onChange={(e) => setFormData(prev => ({ ...prev, title: e.target.value }))}
              className="bg-background/50"
              required
            />
          </div>

          <div className="space-y-2">
            <Label>Type</Label>
            <div className="grid grid-cols-4 gap-2">
              {typeOptions.map(option => (
                <button
                  key={option.value}
                  type="button"
                  onClick={() => setFormData(prev => ({ ...prev, type: option.value }))}
                  className={cn(
                    "flex flex-col items-center gap-1.5 p-3 rounded-xl border transition-all",
                    formData.type === option.value
                      ? "border-primary bg-primary/10 text-primary"
                      : "border-border bg-background/50 text-muted-foreground hover:border-primary/30"
                  )}
                >
                  <option.icon className="w-5 h-5" />
                  <span className="text-xs font-medium">{option.label}</span>
                </button>
              ))}
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="location">
              Location *
              <span className="text-xs text-muted-foreground ml-1">(required)</span>
            </Label>
            <LocationAutocomplete
              value={location?.name || ''}
              onChange={handleLocationChange}
              placeholder="Search for a place..."
              required
            />
            {locationError && (
              <p className="text-xs text-destructive">Please select a location from the dropdown</p>
            )}
          </div>

          <div className="space-y-2">
            <Label htmlFor="notes">Notes</Label>
            <Textarea
              id="notes"
              placeholder="Why does this seem fun? Any details to remember?"
              value={formData.notes}
              onChange={(e) => setFormData(prev => ({ ...prev, notes: e.target.value }))}
              className="bg-background/50 min-h-[80px]"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="link" className="flex items-center gap-1.5">
              <Link className="w-3.5 h-3.5" />
              Link
            </Label>
            <Input
              id="link"
              placeholder="TikTok, website..."
              value={formData.link}
              onChange={(e) => setFormData(prev => ({ ...prev, link: e.target.value }))}
              className="bg-background/50"
            />
          </div>

          <div className="space-y-2">
            <Label className="flex items-center gap-1.5">
              <Tag className="w-3.5 h-3.5" />
              Tags
            </Label>
            <div className="flex gap-2">
              <Input
                placeholder="Add a tag"
                value={tagInput}
                onChange={(e) => setTagInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    handleAddTag();
                  }
                }}
                className="bg-background/50"
              />
              <Button type="button" variant="outline" onClick={handleAddTag}>
                Add
              </Button>
            </div>
            {formData.tags && formData.tags.length > 0 && (
              <div className="flex flex-wrap gap-1.5 mt-2">
                {formData.tags.map(tag => (
                  <span
                    key={tag}
                    onClick={() => handleRemoveTag(tag)}
                    className="text-xs bg-primary/10 text-primary px-2.5 py-1 rounded-full cursor-pointer hover:bg-primary/20 transition-colors"
                  >
                    #{tag} ×
                  </span>
                ))}
              </div>
            )}
          </div>

          <div className="flex justify-end gap-3 pt-4">
            <Button type="button" variant="outline" onClick={handleClose}>
              Cancel
            </Button>
            <Button type="submit" disabled={!formData.title.trim()}>
              Save Date Idea
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
