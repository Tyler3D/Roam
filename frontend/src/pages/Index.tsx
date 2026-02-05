import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDatePins } from '@/hooks/useDatePins';
import { DatePin } from '@/types/datePin';
import { Header } from '@/components/Header';
import { Navigation } from '@/components/Navigation';
import { HomeView } from '@/components/HomeView';
import { MapView } from '@/components/MapView';
import { ListView } from '@/components/ListView';
import { AddDatePinDialog } from '@/components/AddDatePinDialog';
import { DatePinDetail } from '@/components/DatePinDetail';
import { Button } from '@/components/ui/button';
import { useAuth } from '@/auth/AuthContext';

type ViewType = 'home' | 'map' | 'list';

const viewTitles: Record<ViewType, { title: string; subtitle?: string }> = {
  home: { title: 'Date Pins', subtitle: 'Your collection of adventures' },
  map: { title: 'Explore', subtitle: 'Ideas by location' },
  list: { title: 'All Ideas', subtitle: 'Browse everything' },
};

const Index = () => {
  const navigate = useNavigate();
  const { signOutUser } = useAuth();
  const [currentView, setCurrentView] = useState<ViewType>('home');
  const [isAddDialogOpen, setIsAddDialogOpen] = useState(false);
  const [selectedPin, setSelectedPin] = useState<DatePin | null>(null);
  const [isDetailOpen, setIsDetailOpen] = useState(false);

  const {
    pins,
    addPin,
    updateStatus,
    deletePin,
    markAsViewed,
    recentPins,
    forgottenPins,
    pinsWithLocation,
  } = useDatePins();

  const handlePinClick = (pin: DatePin) => {
    setSelectedPin(pin);
    setIsDetailOpen(true);
    markAsViewed(pin.id);
  };

  const { title, subtitle } = viewTitles[currentView];

  const handleSignOut = async () => {
    await signOutUser();
    navigate('/login');
  };

  return (
    <div className="min-h-screen bg-background pb-24">
      <Header
        title={title}
        subtitle={subtitle}
        action={
          <Button variant="ghost" onClick={handleSignOut}>
            Log out
          </Button>
        }
      />

      <main className="max-w-4xl mx-auto px-4 py-6">
        {currentView === 'home' && (
          <HomeView
            recentPins={recentPins}
            forgottenPins={forgottenPins}
            allPins={pins}
            onPinClick={handlePinClick}
          />
        )}

        {currentView === 'map' && (
          <MapView
            pins={pinsWithLocation}
            onPinClick={handlePinClick}
          />
        )}

        {currentView === 'list' && (
          <ListView
            pins={pins}
            onPinClick={handlePinClick}
          />
        )}
      </main>

      <Navigation
        currentView={currentView}
        onViewChange={setCurrentView}
        onAddClick={() => setIsAddDialogOpen(true)}
      />

      <AddDatePinDialog
        open={isAddDialogOpen}
        onOpenChange={setIsAddDialogOpen}
        onSave={addPin}
      />

      <DatePinDetail
        pin={selectedPin}
        open={isDetailOpen}
        onOpenChange={setIsDetailOpen}
        onUpdateStatus={updateStatus}
        onDelete={deletePin}
      />
    </div>
  );
};

export default Index;
