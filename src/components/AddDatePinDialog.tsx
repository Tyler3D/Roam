import { useState } from 'react';
import { DatePinFormData, DatePinType } from '@/types/datePin';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { UtensilsCrossed, Trees, Home, CalendarDays, MapPin, Link, Tag } from 'lucide-react';
import { cn } from '@/lib/utils';

interface AddDatePinDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (data: DatePinFormData) => void;
}

const typeOptions: { value: DatePinType; label: string; icon: typeof UtensilsCrossed }[] = [
  { value: 'restaurant', label: 'Restaurant', icon: UtensilsCrossed },
  { value: 'outdoor', label: 'Outdoor', icon: Trees },
  { value: 'home', label: 'At Home', icon: Home },
  { value: 'event', label: 'Event', icon: CalendarDays },
];

export function AddDatePinDialog({ open, onOpenChange, onSave }: AddDatePinDialogProps) {
  const [formData, setFormData] = useState<DatePinFormData>({
    title: '',
    notes: '',
    link: '',
    locationName: '',
    type: 'restaurant',
    tags: [],
  });
  const [tagInput, setTagInput] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!formData.title.trim()) return;
    onSave(formData);
    setFormData({
      title: '',
      notes: '',
      link: '',
      locationName: '',
      type: 'restaurant',
      tags: [],
    });
    setTagInput('');
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

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[500px] bg-card border-border/50">
        <DialogHeader>
          <DialogTitle className="font-display text-2xl">Save a Date Idea</DialogTitle>
        </DialogHeader>
        
        <form onSubmit={handleSubmit} className="space-y-5 mt-4">
          <div className="space-y-2">
            <Label htmlFor="title">What's the idea?</Label>
            <Input
              id="title"
              placeholder="e.g., Rooftop bar at sunset"
              value={formData.title}
              onChange={(e) => setFormData(prev => ({ ...prev, title: e.target.value }))}
              className="bg-background/50"
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
            <Label htmlFor="notes">Notes</Label>
            <Textarea
              id="notes"
              placeholder="Why does this seem fun? Any details to remember?"
              value={formData.notes}
              onChange={(e) => setFormData(prev => ({ ...prev, notes: e.target.value }))}
              className="bg-background/50 min-h-[80px]"
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="location" className="flex items-center gap-1.5">
                <MapPin className="w-3.5 h-3.5" />
                Location
              </Label>
              <Input
                id="location"
                placeholder="Place name"
                value={formData.locationName}
                onChange={(e) => setFormData(prev => ({ ...prev, locationName: e.target.value }))}
                className="bg-background/50"
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
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
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
