import { DatePin } from '@/types/datePin';
import { MapPin } from 'lucide-react';
import { cn } from '@/lib/utils';

interface MapViewProps {
  pins: DatePin[];
  onPinClick: (pin: DatePin) => void;
}

const typeColors = {
  restaurant: 'bg-primary',
  outdoor: 'bg-accent',
  home: 'bg-highlight',
  event: 'bg-secondary-foreground',
};

export function MapView({ pins, onPinClick }: MapViewProps) {
  // Simple visual map representation
  // In production, you'd integrate with Mapbox or Google Maps
  
  return (
    <div className="relative w-full h-full min-h-[500px] bg-muted/30 rounded-2xl overflow-hidden">
      {/* Map Background Pattern */}
      <div className="absolute inset-0 opacity-20">
        <svg className="w-full h-full" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
              <path d="M 40 0 L 0 0 0 40" fill="none" stroke="currentColor" strokeWidth="0.5" className="text-border" />
            </pattern>
          </defs>
          <rect width="100%" height="100%" fill="url(#grid)" />
        </svg>
      </div>

      {/* Decorative Elements */}
      <div className="absolute inset-0 pointer-events-none">
        <div className="absolute top-[20%] left-[15%] w-32 h-32 bg-accent/5 rounded-full blur-3xl" />
        <div className="absolute bottom-[30%] right-[20%] w-48 h-48 bg-primary/5 rounded-full blur-3xl" />
      </div>

      {/* Pins */}
      <div className="relative w-full h-full">
        {pins.map((pin, index) => {
          // Distribute pins across the map area
          const left = 10 + (index % 4) * 22 + (Math.random() * 10);
          const top = 15 + Math.floor(index / 4) * 25 + (Math.random() * 10);
          
          return (
            <button
              key={pin.id}
              onClick={() => onPinClick(pin)}
              className={cn(
                "absolute transform -translate-x-1/2 -translate-y-full",
                "group cursor-pointer transition-all duration-300 hover:scale-110 hover:z-10",
                "animate-fade-in"
              )}
              style={{ 
                left: `${left}%`, 
                top: `${top}%`,
                animationDelay: `${index * 100}ms`
              }}
            >
              {/* Pin Marker */}
              <div className={cn(
                "flex items-center justify-center w-10 h-10 rounded-full shadow-lg",
                "transition-all duration-300 group-hover:shadow-xl",
                typeColors[pin.type]
              )}>
                <MapPin className="w-5 h-5 text-white" />
              </div>
              
              {/* Pin Label */}
              <div className={cn(
                "absolute left-1/2 -translate-x-1/2 top-full mt-2",
                "bg-card rounded-lg shadow-soft px-3 py-2 min-w-[120px]",
                "opacity-0 group-hover:opacity-100 transition-opacity duration-300",
                "pointer-events-none"
              )}>
                <p className="text-sm font-medium text-foreground truncate text-center">
                  {pin.title}
                </p>
                {pin.location && (
                  <p className="text-xs text-muted-foreground truncate text-center">
                    {pin.location.name}
                  </p>
                )}
              </div>
            </button>
          );
        })}
      </div>

      {/* Empty State */}
      {pins.length === 0 && (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="text-center">
            <MapPin className="w-12 h-12 text-muted-foreground/30 mx-auto mb-3" />
            <p className="text-muted-foreground">No location-based dates yet</p>
            <p className="text-sm text-muted-foreground/60">Add a location to see pins on the map</p>
          </div>
        </div>
      )}

      {/* Map Legend */}
      <div className="absolute bottom-4 left-4 bg-card/90 backdrop-blur-sm rounded-xl p-3 shadow-soft">
        <div className="flex gap-4">
          <div className="flex items-center gap-1.5">
            <div className="w-3 h-3 rounded-full bg-primary" />
            <span className="text-xs text-muted-foreground">Restaurant</span>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-3 h-3 rounded-full bg-accent" />
            <span className="text-xs text-muted-foreground">Outdoor</span>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-3 h-3 rounded-full bg-secondary-foreground" />
            <span className="text-xs text-muted-foreground">Event</span>
          </div>
        </div>
      </div>
    </div>
  );
}
