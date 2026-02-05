import { useRef, useEffect, useState } from 'react';
import { Input } from '@/components/ui/input';
import { MapPin, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';

interface LocationAutocompleteProps {
  value: string;
  onChange: (location: { name: string; lat: number; lng: number } | null) => void;
  placeholder?: string;
  required?: boolean;
  className?: string;
}

export function LocationAutocomplete({
  value,
  onChange,
  placeholder = "Search for a location...",
  required = false,
  className,
}: LocationAutocompleteProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const autocompleteRef = useRef<google.maps.places.Autocomplete | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [inputValue, setInputValue] = useState(value);

  useEffect(() => {
    setInputValue(value);
  }, [value]);

  useEffect(() => {
    if (!inputRef.current || !window.google?.maps?.places) return;

    autocompleteRef.current = new google.maps.places.Autocomplete(inputRef.current, {
      fields: ['name', 'geometry', 'formatted_address'],
    });

    autocompleteRef.current.addListener('place_changed', () => {
      const place = autocompleteRef.current?.getPlace();
      
      if (place?.geometry?.location) {
        const locationData = {
          name: place.name || place.formatted_address || '',
          lat: place.geometry.location.lat(),
          lng: place.geometry.location.lng(),
        };
        setInputValue(locationData.name);
        onChange(locationData);
      }
    });

    return () => {
      if (autocompleteRef.current) {
        google.maps.event.clearInstanceListeners(autocompleteRef.current);
      }
    };
  }, [onChange]);

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = e.target.value;
    setInputValue(newValue);
    
    // Clear location if input is cleared
    if (!newValue.trim()) {
      onChange(null);
    }
  };

  return (
    <div className={cn("relative", className)}>
      <div className="relative">
        <MapPin className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
        <Input
          ref={inputRef}
          type="text"
          value={inputValue}
          onChange={handleInputChange}
          placeholder={placeholder}
          required={required}
          className="pl-9 bg-background/50"
        />
        {isLoading && (
          <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground animate-spin" />
        )}
      </div>
    </div>
  );
}
