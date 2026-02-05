import { DatePin } from '@/types/datePin';
import { DatePinCard } from './DatePinCard';
import { Sparkles, Clock } from 'lucide-react';

interface MemoriesCarouselProps {
  title: string;
  subtitle?: string;
  pins: DatePin[];
  icon?: 'sparkles' | 'clock';
  onPinClick: (pin: DatePin) => void;
}

export function MemoriesCarousel({ 
  title, 
  subtitle, 
  pins, 
  icon = 'sparkles',
  onPinClick 
}: MemoriesCarouselProps) {
  const Icon = icon === 'sparkles' ? Sparkles : Clock;

  if (pins.length === 0) return null;

  return (
    <section className="animate-fade-in">
      <div className="flex items-center gap-2 mb-4">
        <Icon className="w-5 h-5 text-primary" />
        <div>
          <h2 className="font-display text-xl font-semibold text-foreground">{title}</h2>
          {subtitle && (
            <p className="text-sm text-muted-foreground">{subtitle}</p>
          )}
        </div>
      </div>
      
      <div className="relative -mx-4 px-4">
        <div className="flex gap-4 overflow-x-auto pb-4 snap-x snap-mandatory scrollbar-hide">
          {pins.map((pin, index) => (
            <div 
              key={pin.id} 
              className="snap-start"
              style={{ animationDelay: `${index * 100}ms` }}
            >
              <DatePinCard 
                pin={pin} 
                variant="featured" 
                onClick={() => onPinClick(pin)}
              />
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
