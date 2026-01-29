import { useState, useCallback, useMemo } from 'react';
import { DatePin, DatePinFormData, DatePinStatus } from '@/types/datePin';
import { sampleDatePins } from '@/data/sampleDatePins';

export function useDatePins() {
  const [pins, setPins] = useState<DatePin[]>(sampleDatePins);

  const addPin = useCallback((formData: DatePinFormData) => {
    const newPin: DatePin = {
      id: Date.now().toString(),
      title: formData.title,
      notes: formData.notes,
      link: formData.link,
      location: formData.locationName ? {
        name: formData.locationName,
        lat: 40.7128 + (Math.random() - 0.5) * 0.1,
        lng: -74.0060 + (Math.random() - 0.5) * 0.1,
      } : undefined,
      type: formData.type,
      status: 'saved',
      createdAt: new Date(),
      tags: formData.tags,
    };
    setPins(prev => [newPin, ...prev]);
    return newPin;
  }, []);

  const updatePin = useCallback((id: string, updates: Partial<DatePin>) => {
    setPins(prev => prev.map(pin => 
      pin.id === id ? { ...pin, ...updates } : pin
    ));
  }, []);

  const deletePin = useCallback((id: string) => {
    setPins(prev => prev.filter(pin => pin.id !== id));
  }, []);

  const updateStatus = useCallback((id: string, status: DatePinStatus) => {
    updatePin(id, { status });
  }, [updatePin]);

  const markAsViewed = useCallback((id: string) => {
    updatePin(id, { lastViewedAt: new Date() });
  }, [updatePin]);

  // Get recently added pins (last 7 days)
  const recentPins = useMemo(() => {
    const weekAgo = new Date();
    weekAgo.setDate(weekAgo.getDate() - 7);
    return pins
      .filter(pin => pin.createdAt >= weekAgo)
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
  }, [pins]);

  // Get forgotten pins (not viewed in 2+ weeks, not done)
  const forgottenPins = useMemo(() => {
    const twoWeeksAgo = new Date();
    twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);
    return pins
      .filter(pin => {
        const lastViewed = pin.lastViewedAt || pin.createdAt;
        return lastViewed < twoWeeksAgo && pin.status !== 'done';
      })
      .sort(() => Math.random() - 0.5)
      .slice(0, 4);
  }, [pins]);

  // Get pins with locations for map
  const pinsWithLocation = useMemo(() => {
    return pins.filter(pin => pin.location);
  }, [pins]);

  return {
    pins,
    addPin,
    updatePin,
    deletePin,
    updateStatus,
    markAsViewed,
    recentPins,
    forgottenPins,
    pinsWithLocation,
  };
}
