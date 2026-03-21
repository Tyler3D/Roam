import { useState, useCallback, useMemo } from 'react';
import { GoogleMap, useJsApiLoader, MarkerF, InfoWindowF } from '@react-google-maps/api';
import { DatePin } from '@/types/datePin';
import { MapPin, Loader2 } from 'lucide-react';
import { GOOGLE_MAPS_API_KEY, GOOGLE_MAPS_LIBRARIES, DEFAULT_MAP_CENTER, DEFAULT_MAP_ZOOM } from '@/config/maps';
import { MapPinPopup } from '@/components/MapPinPopup';

interface MapViewProps {
  pins: DatePin[];
  onPinClick: (pin: DatePin) => void;
}

const typeColors: Record<string, string> = {
  restaurant: '#E11D48',
  cafe: '#CA8A04',
  bar: '#7C3AED',
  nightlife: '#DB2777',
  outdoor: '#F97316',
  home: '#8B5CF6',
  event: '#3B82F6',
};

const mapContainerStyle = {
  width: '100%',
  height: '100%',
  minHeight: '500px',
  borderRadius: '1rem',
};

const mapOptions: google.maps.MapOptions = {
  disableDefaultUI: false,
  zoomControl: true,
  streetViewControl: false,
  mapTypeControl: false,
  fullscreenControl: true,
  styles: [
    {
      featureType: 'poi',
      elementType: 'labels',
      stylers: [{ visibility: 'off' }],
    },
  ],
};

export function MapView({ pins, onPinClick }: MapViewProps) {
  const [selectedPin, setSelectedPin] = useState<DatePin | null>(null);
  const [_map, setMap] = useState<google.maps.Map | null>(null);

  const { isLoaded, loadError } = useJsApiLoader({
    googleMapsApiKey: GOOGLE_MAPS_API_KEY,
    libraries: GOOGLE_MAPS_LIBRARIES,
  });

  // Calculate center based on pins
  const center = useMemo(() => {
    if (pins.length === 0) return DEFAULT_MAP_CENTER;
    
    const validPins = pins.filter(pin => pin.location);
    if (validPins.length === 0) return DEFAULT_MAP_CENTER;

    const avgLat = validPins.reduce((sum, pin) => sum + (pin.location?.lat || 0), 0) / validPins.length;
    const avgLng = validPins.reduce((sum, pin) => sum + (pin.location?.lng || 0), 0) / validPins.length;
    
    return { lat: avgLat, lng: avgLng };
  }, [pins]);

  const onLoad = useCallback((map: google.maps.Map) => {
    setMap(map);
    
    // Fit bounds to show all pins
    if (pins.length > 0) {
      const bounds = new google.maps.LatLngBounds();
      pins.forEach(pin => {
        if (pin.location) {
          bounds.extend({ lat: pin.location.lat, lng: pin.location.lng });
        }
      });
      map.fitBounds(bounds, 50);
      
      // Don't zoom in too much
      const listener = google.maps.event.addListener(map, 'idle', () => {
        const zoom = map.getZoom();
        if (zoom && zoom > 15) {
          map.setZoom(15);
        }
        google.maps.event.removeListener(listener);
      });
    }
  }, [pins]);

  const onUnmount = useCallback(() => {
    setMap(null);
  }, []);

  const handleMarkerClick = (pin: DatePin) => {
    setSelectedPin(pin);
  };

  const handleInfoWindowClose = () => {
    setSelectedPin(null);
  };

  const handleViewDetails = (pin: DatePin) => {
    setSelectedPin(null);
    onPinClick(pin);
  };

  // Create custom marker icon as data URL
  const createMarkerIcon = (color: string) => {
    const svg = `
      <svg width="32" height="40" viewBox="0 0 32 40" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M16 0C7.164 0 0 7.164 0 16c0 10 16 24 16 24s16-14 16-24c0-8.836-7.164-16-16-16z" fill="${color}"/>
        <circle cx="16" cy="16" r="6" fill="white"/>
      </svg>
    `;
    return `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(svg)}`;
  };

  if (loadError) {
    return (
      <div className="relative w-full h-full min-h-[500px] bg-muted/30 rounded-2xl overflow-hidden flex items-center justify-center">
        <div className="text-center">
          <MapPin className="w-12 h-12 text-destructive/50 mx-auto mb-3" />
          <p className="text-muted-foreground">Failed to load Google Maps</p>
          <p className="text-sm text-muted-foreground/60">Please check your API key</p>
        </div>
      </div>
    );
  }

  if (!isLoaded) {
    return (
      <div className="relative w-full h-full min-h-[500px] bg-muted/30 rounded-2xl overflow-hidden flex items-center justify-center">
        <div className="text-center">
          <Loader2 className="w-12 h-12 text-primary animate-spin mx-auto mb-3" />
          <p className="text-muted-foreground">Loading map...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="relative w-full h-full min-h-[500px] rounded-2xl overflow-hidden">
      <GoogleMap
        mapContainerStyle={mapContainerStyle}
        center={center}
        zoom={DEFAULT_MAP_ZOOM}
        onLoad={onLoad}
        onUnmount={onUnmount}
        options={mapOptions}
        onClick={() => setSelectedPin(null)}
      >
        {pins.map((pin) => {
          if (!pin.location) return null;
          
          return (
            <MarkerF
              key={pin.id}
              position={{ lat: pin.location.lat, lng: pin.location.lng }}
              onClick={() => handleMarkerClick(pin)}
              icon={{
                url: createMarkerIcon(typeColors[pin.type] ?? typeColors.event),
                scaledSize: new google.maps.Size(32, 40),
                anchor: new google.maps.Point(16, 40),
              }}
            />
          );
        })}

        {selectedPin && selectedPin.location && (
          <InfoWindowF
            position={{ lat: selectedPin.location.lat, lng: selectedPin.location.lng }}
            onCloseClick={handleInfoWindowClose}
            options={{
              pixelOffset: new google.maps.Size(0, -40),
              disableAutoPan: false,
            }}
          >
            <MapPinPopup
              pin={selectedPin}
              onClose={handleInfoWindowClose}
              onViewDetails={() => handleViewDetails(selectedPin)}
            />
          </InfoWindowF>
        )}
      </GoogleMap>

      {/* Empty State */}
      {pins.length === 0 && (
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
          <div className="text-center bg-card/90 backdrop-blur-sm rounded-xl p-6 shadow-lg">
            <MapPin className="w-12 h-12 text-muted-foreground/30 mx-auto mb-3" />
            <p className="text-muted-foreground">No location-based dates yet</p>
            <p className="text-sm text-muted-foreground/60">Add a date with a location to see it on the map</p>
          </div>
        </div>
      )}

      {/* Map Legend */}
      <div className="absolute bottom-4 left-4 bg-card/90 backdrop-blur-sm rounded-xl p-3 shadow-lg max-w-[min(100%-2rem,320px)]">
        <div className="flex flex-wrap gap-x-3 gap-y-2">
          {(
            [
              ['restaurant', 'Restaurant'],
              ['cafe', 'Café'],
              ['bar', 'Bar'],
              ['nightlife', 'Nightlife'],
              ['outdoor', 'Outdoor'],
              ['home', 'Home'],
              ['event', 'Event'],
            ] as const
          ).map(([key, label]) => (
            <div key={key} className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded-full shrink-0" style={{ backgroundColor: typeColors[key] }} />
              <span className="text-xs text-muted-foreground">{label}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
