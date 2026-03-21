export type DatePinType =
  | 'restaurant'
  | 'cafe'
  | 'bar'
  | 'nightlife'
  | 'outdoor'
  | 'home'
  | 'event';
export type DatePinStatus = 'saved' | 'planned' | 'done';

export interface DatePin {
  id: string;
  title: string;
  notes?: string;
  link?: string;
  location?: {
    name: string;
    lat: number;
    lng: number;
  };
  type: DatePinType;
  status: DatePinStatus;
  createdAt: Date;
  lastViewedAt?: Date;
  tags?: string[];
  imageUrl?: string;
}

export interface DatePinFormData {
  title: string;
  notes?: string;
  link?: string;
  locationName?: string;
  locationLat?: number;
  locationLng?: number;
  type: DatePinType;
  tags?: string[];
}
