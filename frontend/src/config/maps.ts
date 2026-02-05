export const GOOGLE_MAPS_API_KEY = import.meta.env.VITE_GOOGLE_MAPS_API_KEY ?? '';

export const GOOGLE_MAPS_LIBRARIES: ("places")[] = ["places"];

export const DEFAULT_MAP_CENTER = {
  lat: 40.7128,
  lng: -74.0060,
};

export const DEFAULT_MAP_ZOOM = 12;
